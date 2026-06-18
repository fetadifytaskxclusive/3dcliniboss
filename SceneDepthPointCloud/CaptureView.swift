import SwiftUI
import AVFoundation

@available(iOS 17.0, *)
@MainActor
struct CaptureView: View {
    @EnvironmentObject var manager: ScannerSessionManager
    @StateObject private var avManager: AVCaptureManager
    
    @State private var isCompleted = false
    @State private var torchOn = false
    @State private var ovalPulse = false
    @State private var arrowOffset: CGFloat = 0.0
    
    var isHeadScan: Bool = false

    var imagesFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Scans/Images", isDirectory: true)
    }

    var checkpointFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Scans/Checkpoints", isDirectory: true)
    }
    
    init(isHeadScan: Bool = false) {
        self.isHeadScan = isHeadScan
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("Scans/Images", isDirectory: true)
        _avManager = StateObject(wrappedValue: AVCaptureManager(imagesFolder: folder))
    }

    var body: some View {
        ZStack {
            if isCompleted {
                // Tela de sucesso
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(AppConfig.cliniBossPrimary)
                        
                    Text("Fotos Capturadas!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        
                    Text("Tudo pronto para gerar o seu modelo 3D.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                                            
                    actionButton("Processar 3D", color: AppConfig.cliniBossPrimary) {
                    }
                }
            } else {
                CameraPreviewView(session: avManager.captureSession)
                    .edgesIgnoringSafeArea(.all)
                
                // ===== GUIDED HEAD SCAN OVERLAY =====
                if isHeadScan {
                    guidedOverlay
                } else if avManager.isCapturing {
                    // Modo manual (não head scan): contagem simples
                    manualCountOverlay
                }
                
                // Lanterna (sempre visivel)
                VStack {
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
                    
                    // Tratamento de Erros da Câmera
                    if let errorMsg = avManager.errorMessage {
                        Text(errorMsg)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(.bottom, 20)
                    }
                    
                    stateButtons
                }
            }
        }
        .onAppear {
            setupFolders()
            avManager.startCamera()
        }
        .onDisappear {
            setTorch(false)
            avManager.stopContinuousCapture()
            avManager.stopCamera()
        }
        .onChange(of: avManager.scanPhase) { _, newPhase in
            if newPhase == .completed {
                setTorch(false)
                isCompleted = true
            }
        }
        .navigationDestination(isPresented: $isCompleted) {
            ReconstructionView(imagesFolder: imagesFolder)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Guided Overlay (Head Scan)
    
    @ViewBuilder
    private var guidedOverlay: some View {
        let ovalColor: Color = (avManager.scanPhase != .waitingForFace) ? AppConfig.cliniBossPrimary : (avManager.isFaceFramed ? AppConfig.cliniBossPrimary : .white)
        
        GeometryReader { geo in
            let ovalWidth: CGFloat = geo.size.width * 0.62
            let ovalHeight: CGFloat = ovalWidth * 1.35
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.42)
            
            ZStack {
                // Dimmed background with oval cutout
                Color.black.opacity(0.35)
                    .edgesIgnoringSafeArea(.all)
                    .mask(
                        ZStack {
                            Rectangle().fill(Color.white)
                            Ellipse()
                                .frame(width: ovalWidth + 4, height: ovalHeight + 4)
                                .position(center)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    )
                
                // Oval border (pulsing)
                Ellipse()
                    .stroke(ovalColor, lineWidth: 3)
                    .frame(width: ovalWidth, height: ovalHeight)
                    .position(center)
                    .scaleEffect(ovalPulse ? 1.02 : 0.98)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: ovalPulse)
                    .onAppear { ovalPulse = true }
                
                // Dynamic instruction chip at top
                VStack(spacing: 6) {
                    guidedInstructionChip
                        .padding(.top, 55)
                    Spacer()
                }
                
                // Directional arrow overlays
                if avManager.scanPhase == .firstLoop || avManager.scanPhase == .secondLoop {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(AppConfig.cliniBossPrimary.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 4)
                            .padding(.trailing, 16)
                            .offset(x: arrowOffset)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: arrowOffset)
                            .onAppear { arrowOffset = 10 }
                    }
                    .position(x: geo.size.width / 2, y: center.y)
                }
                
                if avManager.scanPhase == .waitingForPitch {
                    // Phone tilt indicator
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 44))
                            .foregroundColor(.yellow)
                            .rotationEffect(.degrees(-30))
                        
                        Text("Incline a câmera para baixo")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        
                        Text("Mire de cima na cabeça do paciente")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .position(center)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Guided Instruction Chip
    
    @ViewBuilder
    private var guidedInstructionChip: some View {
        let (icon, title, subtitle) = guidedTexts
        
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(chipColor.opacity(0.88))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
    
    private var guidedTexts: (String, String, String) {
        switch avManager.scanPhase {
        case .waitingForFace:
            return ("faceid", "Enquadre o rosto no oval", "Posicione o paciente no centro")
        case .firstLoop:
            let pct = Int(avManager.yawProgress * 100)
            return ("arrow.trianglehead.2.counterclockwise.rotate.90", "1ª Volta — \(pct)%", "Gire ao redor do paciente")
        case .waitingForPitch:
            return ("iphone.gen3.radiowaves.left.and.right", "Incline o celular para baixo", "Mire de cima na cabeça")
        case .secondLoop:
            let pct = Int(avManager.yawProgress * 100)
            return ("arrow.trianglehead.2.counterclockwise.rotate.90", "2ª Volta (topo) — \(pct)%", "Continue girando de cima")
        case .completed:
            return ("checkmark.seal.fill", "Captura Completa!", "")
        }
    }
    
    private var chipColor: Color {
        switch avManager.scanPhase {
        case .waitingForFace:
            return avManager.isFaceFramed ? AppConfig.cliniBossPrimary : Color.white.opacity(0.3)
        default:
            return AppConfig.cliniBossPrimary
        }
    }
    
    // MARK: - Manual Count Overlay (non head-scan)
    
    @ViewBuilder
    private var manualCountOverlay: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("Fotos: \(avManager.imageCount)")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    
                if avManager.imageCount < 30 {
                    Text("Mínimo: 30 fotos")
                        .font(.caption.bold())
                        .foregroundColor(Color.red.opacity(0.9))
                } else {
                    Text("Qualidade OK!")
                        .font(.caption.bold())
                        .foregroundColor(Color.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
            .cornerRadius(16)
            .padding(.top, 50)
            
            Spacer()
        }
    }

    // MARK: - State Buttons

    @ViewBuilder
    private var stateButtons: some View {
        if !avManager.isCapturing {
            // Estado READY (Antes de começar)
            actionButton(isHeadScan ? "Iniciar Escaneamento Guiado" : "Começar as Fotos",
                         color: AppConfig.cliniBossPrimary) {
                avManager.startContinuousCapture(isGuided: isHeadScan)
            }
        } else if isHeadScan {
            // No modo guiado: apenas botão de Refazer (o sistema auto-completa)
            HStack {
                Button {
                    avManager.stopContinuousCapture()
                    setupFolders()
                    avManager.startContinuousCapture(isGuided: true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                        Text("Refazer")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                    .shadow(radius: 6)
                }
                .padding(.leading, 24)
                .padding(.bottom, 40)
                
                Spacer()
                
                // Botão de emergência para finalizar manualmente (caso tenha > 30 fotos)
                if avManager.imageCount >= 30 {
                    Button {
                        avManager.stopContinuousCapture()
                        setTorch(false)
                        isCompleted = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("Concluir")
                                .font(.subheadline.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppConfig.cliniBossPrimary)
                        .clipShape(Capsule())
                        .shadow(radius: 6)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 40)
                }
            }
        } else {
            // Modo manual: botões originais
            HStack {
                Button {
                    avManager.stopContinuousCapture()
                    setupFolders()
                    avManager.startContinuousCapture(isGuided: false)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 56, height: 56)
                            .shadow(radius: 6)
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.leading, 32)
                .padding(.bottom, 50)
                
                Spacer()
                
                Button {
                    avManager.stopContinuousCapture()
                    setTorch(false)
                    isCompleted = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(avManager.imageCount < 30 ? Color.gray.opacity(0.5) : AppConfig.cliniBossPrimary)
                            .frame(width: 64, height: 64)
                            .shadow(radius: 6)
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(avManager.imageCount < 30 ? .white.opacity(0.5) : .white)
                    }
                }
                .disabled(avManager.imageCount < 30)
                .padding(.trailing, 32)
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Session Setup

    private func setupFolders() {
        do {
            for folder in [imagesFolder, checkpointFolder] {
                if FileManager.default.fileExists(atPath: folder.path) {
                    try FileManager.default.removeItem(at: folder)
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            print("[Capture] Error setting up folders: \(error)")
        }
    }

    // MARK: - Action Button Builder

    @ViewBuilder
    private func actionButton(
        _ title: String,
        color: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(disabled ? Color.gray : color)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .opacity(disabled ? 0.6 : 1.0)
        }
        .disabled(disabled)
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
    }

    // MARK: - Torch

    private func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("[Torch] Error: \(error)")
        }
    }
}
