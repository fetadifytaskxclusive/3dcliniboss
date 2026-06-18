import Foundation
import AVFoundation
import UIKit
import Vision
import CoreMotion

enum ScanPhase {
    case waitingForFace
    case firstLoop
    case waitingForPitch
    case secondLoop
    case completed
}

@MainActor
class AVCaptureManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var imageCount = 0
    @Published var isCapturing = false
    @Published var errorMessage: String? = nil
    
    // Novos estados interativos
    @Published var scanPhase: ScanPhase = .waitingForFace
    @Published var isFaceFramed = false
    @Published var yawProgress: Double = 0.0 // 0.0 a 1.0
    
    private var isGuidedMode: Bool = false
    
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    let imagesFolder: URL
    private var captureTimer: Timer?
    
    private let motionManager = CMMotionManager()
    private var lastYaw: Double? = nil
    private var accumulatedYaw: Double = 0.0
    
    init(imagesFolder: URL) {
        self.imagesFolder = imagesFolder
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        // Setup Video Input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            errorMessage = "Câmera principal não suportada ou sem permissão."
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoDeviceInput)
        
        // Setup Photo Output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
        } else {
            errorMessage = "Não foi possível adicionar a saída de foto."
        }
        
        // Setup Video Data Output for Vision Tracking
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            if let connection = videoDataOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    func startCamera() {
        Task.detached { [weak self] in
            self?.captureSession.startRunning()
            await MainActor.run { self?.isSessionRunning = true }
        }
    }
    
    func stopCamera() {
        captureSession.stopRunning()
        isSessionRunning = false
        stopContinuousCapture()
    }
    
    func startContinuousCapture(isGuided: Bool = false) {
        guard isSessionRunning else { return }
        self.isGuidedMode = isGuided
        
        if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesFolder.path) {
            imageCount = files.count
        } else {
            imageCount = 0
        }
        
        isCapturing = true
        scanPhase = .waitingForFace
        yawProgress = 0.0
        accumulatedYaw = 0.0
        lastYaw = nil
        
        // Start Motion Tracking
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion else { return }
                self.handleMotionUpdate(motion)
            }
        }
        
        // Timer de 0.3s (só tira foto se enquadrado)
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.triggerPhoto()
        }
    }
    
    func stopContinuousCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
        motionManager.stopDeviceMotionUpdates()
        isCapturing = false
    }
    
    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        guard isCapturing, isGuidedMode, scanPhase != .completed else { return }
        
        let pitchDegrees = motion.attitude.pitch * 180 / .pi
        let currentYaw = motion.attitude.yaw
        
        if let last = lastYaw {
            var delta = currentYaw - last
            if delta > .pi { delta -= 2 * .pi }
            else if delta < -.pi { delta += 2 * .pi }
            
            // Só acumula giro se for a hora certa
            if scanPhase == .firstLoop || scanPhase == .secondLoop {
                accumulatedYaw += abs(delta)
            }
        }
        lastYaw = currentYaw
        
        let progress = accumulatedYaw / (2 * .pi)
        
        if scanPhase == .firstLoop {
            yawProgress = min(progress, 1.0)
            if yawProgress >= 1.0 {
                scanPhase = .waitingForPitch
                accumulatedYaw = 0.0
                yawProgress = 0.0
            }
        } else if scanPhase == .waitingForPitch {
            // Portrait perfeito = 90 graus. Inclinar a câmera para baixo = reduz o pitch
            if pitchDegrees < 70.0 {
                scanPhase = .secondLoop
                lastYaw = currentYaw
            }
        } else if scanPhase == .secondLoop {
            yawProgress = min(progress, 1.0)
            if yawProgress >= 1.0 {
                scanPhase = .completed
                stopContinuousCapture()
            }
        }
    }
    
    private func triggerPhoto() {
        if isGuidedMode {
            guard scanPhase == .firstLoop || scanPhase == .secondLoop else { return }
        }
        
        var settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
        settings.isHighResolutionPhotoEnabled = true
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = true
            settings.embedsDepthDataInPhoto = true
        }
        settings.photoQualityPrioritization = .speed
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension AVCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // A orientação aqui pode precisar de ajustes dependendo de como o buffer sai, 
        // mas .right é o padrao para lidar com portrait traseiro.
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        let request = VNDetectFaceRectanglesRequest { [weak self] req, error in
            guard let self = self else { return }
            
            let results = req.results as? [VNFaceObservation] ?? []
            let isCentered = results.contains { box in
                // A boundingBox tem origem em bottom-left (0,0) ate top-right (1,1)
                // Vamos considerar um oval generoso no centro: X entre 0.3 e 0.7
                box.boundingBox.midX > 0.25 && box.boundingBox.midX < 0.75 &&
                box.boundingBox.midY > 0.25 && box.boundingBox.midY < 0.75
            }
            
            Task { @MainActor in
                self.isFaceFramed = isCentered
                if self.isCapturing && self.isGuidedMode && self.scanPhase == .waitingForFace && isCentered {
                    self.scanPhase = .firstLoop
                    self.accumulatedYaw = 0.0
                    self.yawProgress = 0.0
                }
            }
        }
        
        try? requestHandler.perform([request])
    }
}

extension AVCaptureManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[AVCapture] Erro foto: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        
        let filename = "IMG_\(Date().timeIntervalSince1970).heic"
        let fileUrl = imagesFolder.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileUrl)
            Task { @MainActor in
                self.imageCount += 1
            }
        } catch {
            print("[AVCapture] Erro salvar foto: \(error)")
        }
    }
}
