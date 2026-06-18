import SwiftUI
import RealityKit
import AVFoundation
import ARKit
import SceneKit

@available(iOS 17.0, *)
@MainActor
struct ExperimentalCaptureView: View {
    @EnvironmentObject var manager: ScannerSessionManager
    @State private var isCompleted = false
    @State private var torchOn = false
    
    // Novas propriedades para foto frontal e Molde de Cabeça (LiDAR)
    @State private var needsFrontPhoto = true
    @State private var showFrontPhotoGuide = false
    @State private var frontPhotoCaptured = false
    
    // ARKit tracking para Molde de Cabeça (LiDAR Traseiro)
    @State private var headCoordinator = HeadMeshCoordinator()

    var body: some View {
        ZStack {
            ObjectCaptureView(session: manager.experimentalSession)
                .edgesIgnoringSafeArea(.all)

            // Overlay para Guia de Foto Frontal
            if showFrontPhotoGuide {
                frontPhotoGuideOverlay
            }

            VStack {
                // Torch toggle — top-right
                HStack {
                    Spacer()
                    Button { toggleTorch() } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 22))
                            .foregroundColor(torchOn ? .yellow : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }

                Spacer()

                if case .ready = manager.experimentalSession.state {
                    actionButton("Iniciar Scanner Experimental", color: .purple) {
                        manager.experimentalSession.startDetecting()
                    }
                } else if case .detecting = manager.experimentalSession.state {
                    if !frontPhotoCaptured {
                        actionButton("Capturar Foto Frontal (Referência)", color: .blue) {
                            showFrontPhotoGuide = true
                        }
                    } else {
                        // Quando já tirou a foto frontal e está detectando, o sistema 
                        // mostrará uma mensagem de "Ajustando Bounding Box..."
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Ajustando Caixa para Cabeça...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(15)
                        .padding(.bottom, 50)
                        .onAppear {
                            // Delay para dar tempo do ARKit estabilizar a caixa na cabeça
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if case .detecting = manager.experimentalSession.state {
                                    print("[Experimental] Auto-Locking and Starting Capture.")
                                    manager.experimentalSession.startCapturing()
                                }
                            }
                        }
                    }
                } else if case .capturing = manager.experimentalSession.state {
                    HStack {
                        Spacer()
                        Button {
                            manager.experimentalSession.finish()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 64, height: 64)
                                    .shadow(radius: 6)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, 28)
                        .padding(.bottom, 50)
                    }
                } else if case .completed = manager.experimentalSession.state {
                    actionButton("Processar Malha Experimental →", color: .orange) {
                        setTorch(false)
                        isCompleted = true
                    }
                }
            }
        }
        .onAppear {
            setupAndStartSession()
        }
        .onDisappear {
            setTorch(false)
        }
        .onChange(of: isCompleted) { newValue in
            // Se o usuário cancelou na ReconstructionView e voltou pra cá, precisamos resetar tudo
            if newValue == false {
                setupAndStartSession()
            }
        }
        .navigationDestination(isPresented: $isCompleted) {
            ReconstructionView(imagesFolder: manager.experimentalImagesFolder)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Photo Reference Overlay
    
    private var frontPhotoGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("FOTO DE REFERÊNCIA FRONTAL")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                
                Text("Alinhe o rosto da pessoa dentro do círculo.")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 3)
                    .frame(width: 280, height: 280)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                
                Button(action: {
                    takeFrontalReferencePhoto()
                }) {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 70, height: 70)
                        Circle().stroke(Color.blue, lineWidth: 4).frame(width: 80, height: 80)
                    }
                }
                .padding(.top, 20)
                
                Button("Cancelar") {
                    showFrontPhotoGuide = false
                    stopHeadMeshTracking()
                }
                .foregroundColor(.white)
                .padding(.top, 10)
            }
        }
        .onAppear {
            startHeadMeshTracking()
        }
    }

    // MARK: - Logic
    
    // MARK: - Logic
    
    private func startHeadMeshTracking() {
        headCoordinator.startTracking()
    }
    
    private func stopHeadMeshTracking() {
        headCoordinator.stopTracking()
    }

    private func setupAndStartSession() {
        // GARANTIA: Sempre recriar a sessão do zero para evitar vazar estado do scanner anterior
        manager.resetExperimental()
        
        do {
            // LIMPAR TUDO - As pastas precisam estar zeradas
            if FileManager.default.fileExists(atPath: manager.experimentalImagesFolder.path) {
                try FileManager.default.removeItem(at: manager.experimentalImagesFolder)
            }
            if FileManager.default.fileExists(atPath: manager.experimentalCheckpointFolder.path) {
                try FileManager.default.removeItem(at: manager.experimentalCheckpointFolder)
            }
            
            try FileManager.default.createDirectory(at: manager.experimentalImagesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: manager.experimentalCheckpointFolder, withIntermediateDirectories: true)
            
            var cfg = ObjectCaptureSession.Configuration()
            cfg.checkpointDirectory = manager.experimentalCheckpointFolder
            manager.experimentalSession.start(imagesDirectory: manager.experimentalImagesFolder, configuration: cfg)
            
            // Resetar estados locais da UI
            self.frontPhotoCaptured = false
            self.showFrontPhotoGuide = false
            self.torchOn = false
        } catch {
            print("[Experimental] Error: \(error)")
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(color)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
    }

    // MARK: - Reference Capture Logic
    
    private func takeFrontalReferencePhoto() {
        // Capturar a geometria volumétrica atual do LiDAR traseiro
        if let currentMesh = headCoordinator.currentHeadMesh {
            manager.capturedHeadMesh = currentMesh
            print("[Experimental] Head Volume (LiDAR) Captured.")
        } else {
            print("[Experimental] Warning: No LiDAR Mesh detected. Check if device has LiDAR.")
        }
        
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        withAnimation {
            showFrontPhotoGuide = false
            frontPhotoCaptured = true
        }
        
        stopHeadMeshTracking()
        print("[Experimental] Frontal Reference (Rear Camera) Marked.")
    }

    private func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("[Torch] Experimental Error: \(error)")
        }
    }
}

// MARK: - HeadMeshCoordinator
// Gerencia o LiDAR traseiro em paralelo para capturar o volume da cabeça
@MainActor
class HeadMeshCoordinator: NSObject, ARSessionDelegate {
    private let session = ARSession()
    var currentHeadMesh: ARMeshAnchor?
    
    override init() {
        super.init()
        session.delegate = self
    }
    
    func startTracking() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        
        // Ativando Scene Reconstruction (LiDAR)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        configuration.frameSemantics = .sceneDepth
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func stopTracking() {
        session.pause()
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Pegar o mesh que estiver mais próximo do centro ou o mais recente detectado
        if let meshAnchor = anchors.compactMap({ $0 as? ARMeshAnchor }).first {
            self.currentHeadMesh = meshAnchor
        }
    }
}
