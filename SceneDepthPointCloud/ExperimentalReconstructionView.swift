import SwiftUI
import RealityKit
import os

@available(iOS 17.0, *)
struct ExperimentalReconstructionView: View {
    let imagesFolder: URL
    
    @State private var progress: Double = 0.0
    @State private var isProcessing: Bool = true
    @State private var modelURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var showingPreview = false
    
    private let logger = Logger(subsystem: "com.example.apple-samplecode.SceneDepthPointCloud", category: "ExperimentalReconstruction")
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Reconstrução Experimental")
                .font(.title)
                .bold()
                .foregroundColor(.purple)
            
            if isProcessing {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                    .padding(.horizontal, 40)
                    
                Text("\(Int(progress * 100))%")
                    .font(.headline)
            } else if let modelURL = modelURL {
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.purple)
                
                Text("Cozimento Concluído!")
                    .font(.headline)
                
                ShareLink(item: modelURL) {
                    Label("Exportar Modelo Experimental USDZ", systemImage: "sparkles")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                Button(action: {
                    showingPreview = true
                }) {
                    Label("Visualizar em 3D (AR)", systemImage: "arkit")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .sheet(isPresented: $showingPreview) {
                    ModelPreviewSheet(url: modelURL, isPresented: $showingPreview)
                }
            } else if let error = errorMessage {
                Text("Erro Experimental: \(error)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .task {
            await processModel()
        }
        .navigationBarBackButtonHidden(isProcessing)
    }
    
    private func processModel() async {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outputUrl = documentsPath.appendingPathComponent("ExperimentalScans/Models/experimental-\(UUID().uuidString).usdz")
        
        try? FileManager.default.createDirectory(at: documentsPath.appendingPathComponent("ExperimentalScans/Models"), withIntermediateDirectories: true, attributes: nil)
        
        do {
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high
            // Futuros testes experimentais vão mexer nessa config
            
            let session = try PhotogrammetrySession(input: imagesFolder, configuration: config)
            
            // Revertendo para parâmetros compatíveis com iOS
            let request = PhotogrammetrySession.Request.modelFile(url: outputUrl, detail: .reduced)
            
            Task {
                for try await output in session.outputs {
                    switch output {
                    case .processingComplete:
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            // Guard: Apple sends .processingComplete even after failures.
                            // Only treat as success if the file actually exists on disk.
                            if FileManager.default.fileExists(atPath: outputUrl.path) {
                                self.modelURL = outputUrl
                            } else if self.errorMessage == nil {
                                self.errorMessage = "O processamento falhou. Certifique-se de escanear o objeto por completo, com boa iluminação e superfície com textura."
                            }
                        }
                    case .requestError(_, let error):
                        DispatchQueue.main.async {
                            // Store error; processingComplete will set isProcessing = false
                            self.errorMessage = error.localizedDescription
                        }
                    case .processingCancelled:
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            self.errorMessage = "Cancelado"
                        }
                    case .requestProgress(_, let fractionComplete):
                        DispatchQueue.main.async {
                            self.progress = fractionComplete
                        }
                    default:
                        break
                    }
                }
            }
            
            try session.process(requests: [request])
            
        } catch {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.errorMessage = "Falha ao iniciar experimento: \(error.localizedDescription)"
            }
        }
    }
}
