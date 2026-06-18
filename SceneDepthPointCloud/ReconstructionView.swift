import SwiftUI
import RealityKit
import os
import ModelIO

@available(iOS 17.0, *)
struct ReconstructionView: View {
    let imagesFolder: URL
    @EnvironmentObject var bridgeManager: WebBridgeManager
    @Environment(\.dismiss) var dismiss
    
    @State private var progress: Double = 0.0
    @State private var isProcessing: Bool = true
    @State private var isUploading: Bool = false
    @State private var usdzFileURL: URL? = nil
    @State private var glbFileURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var showingPreview = false
    
    private let logger = Logger(subsystem: "com.example.apple-samplecode.SceneDepthPointCloud", category: "Reconstruction")
    
    var body: some View {
        VStack(spacing: 30) {
            Text(isUploading ? "Enviando para o CliniBoss..." : (isProcessing && progress >= 0.4 && progress < 0.85 ? "Preparando modelo clínico..." : "Processando Modelo 3D"))
                .font(.title)
                .bold()
            
            if isProcessing || isUploading {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal, 40)
                    
                Text("\(Int(progress * 100))%")
                    .font(.headline)
            } else if let usdzURL = usdzFileURL {
                Text("Confirme o Modelo")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                QuickLookPreview(url: usdzURL)
                    .frame(maxHeight: .infinity)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 10)
                    .padding(.horizontal, 20)
                
                VStack(spacing: 12) {
                    Button(action: {
                        self.handleConfirmAndUpload()
                    }) {
                        Label(bridgeManager.currentRequest != nil ? "Processar e Enviar" : "Testar Processamento Offline", systemImage: "wand.and.stars")
                            .font(.headline)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(AppConfig.cliniBossPrimary)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    
                    ShareLink(item: usdzURL) {
                        Label("Exportar Modelo USDZ (Debug)", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    
                    Button(action: {
                        if let req = bridgeManager.currentRequest {
                            bridgeManager.sendCancelResult(requestId: req.requestId ?? "")
                        }
                        bridgeManager.isScanning = false
                        dismiss()
                    }) {
                        Label("Descartar e Refazer", systemImage: "trash")
                            .font(.headline)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            } else if let rawError = errorMessage {
                let errorData = formattedError(rawError)
                
                VStack(spacing: 16) {
                    Image(systemName: errorData.icon)
                        .font(.system(size: 60))
                        .foregroundColor(errorData.color)
                        
                    Text(errorData.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        
                    Text(errorData.message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 20)
                
                Button(action: {
                    if let req = bridgeManager.currentRequest {
                        bridgeManager.sendErrorResult(requestId: req.requestId ?? "", errorCode: "SCAN_FAILED", errorMessage: rawError)
                        bridgeManager.isScanning = false
                        dismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    Text("Tentar Novamente")
                        .font(.headline)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 40)
            }
        }
        .task {
            await processModel()
        }
        .navigationBarBackButtonHidden(isProcessing || isUploading)
    }
    
    // MARK: - Error Formatter
    
    private func formattedError(_ rawError: String) -> (title: String, message: String, icon: String, color: Color) {
        let errStr = rawError.lowercased()
        
        if errStr.contains("error 1") || errStr.contains("session failed") || errStr.contains("invalid input") {
            return (
                title: "Captura Incompleta",
                message: "Não tiramos fotos sobrepostas o suficiente para montar o 3D. Gire devagar ao redor do objeto e certifique-se de que a caixa verde piscou capturando tudo.",
                icon: "camera.viewfinder",
                color: .orange
            )
        } else if errStr.contains("cancelado") {
            return (
                title: "Processamento Cancelado",
                message: "O mapeamento foi interrompido antes do fim.",
                icon: "xmark.octagon.fill",
                color: .gray
            )
        } else if errStr.contains("glb") {
            return (
                title: "Falha na Conversão",
                message: "O modelo 3D foi gerado mas falhou ao ser otimizado para a Web. (\(rawError))",
                icon: "cube.transparent.fill",
                color: .red
            )
        } else if errStr.contains("rosto") || errStr.contains("facenotfound") {
            return (
                title: "Rosto Não Detectado",
                message: "Não foi possível detectar os contornos faciais do paciente. Certifique-se de que o paciente está centralizado, sob boa iluminação uniforme e sem coberturas no rosto.",
                icon: "face.dashed",
                color: .orange
            )
        } else {
            // Default raw fallback
            return (
                title: "Erro no Processamento",
                message: rawError,
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }
    
    @State private var converterEngine = GLBConverterEngine()
    
    private func processModel() async {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let uuidStr = UUID().uuidString
        
        let outputDir = documentsPath.appendingPathComponent("Scans/Models/\(uuidStr)")
        let usdzUrl = outputDir.appendingPathComponent("scan.usdz")
        let outputUrl = outputDir.appendingPathComponent("scan.obj")
        
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
        
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesFolder.path)) ?? []
        let imageFiles = files.filter { $0.hasSuffix(".heic") || $0.hasSuffix(".jpg") }
        if imageFiles.count < 25 {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.errorMessage = "Foram repassadas apenas \(imageFiles.count) fotos para o motor. São necessárias pelo menos 25 fotos úteis para iniciar."
            }
            return
        }
        
        do {
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high
            config.sampleOrdering = .sequential
            config.isObjectMaskingEnabled = false
            
            print("📸 [3D_Engine] Iniciando PhotogrammetrySession (Config: Sequencial, Masking=\(config.isObjectMaskingEnabled))...")
            print("📂 [3D_Engine] Lendo imagens de: \(imagesFolder.path)")
            
            let session = try PhotogrammetrySession(input: imagesFolder, configuration: config)
            let usdzRequest = PhotogrammetrySession.Request.modelFile(url: usdzUrl, detail: .reduced)
            
            Task {
                for try await output in session.outputs {
                    switch output {
                    case .processingComplete:
                        print("✅ [3D_Engine] USDZ gerado nativamente pelo PhotogrammetrySession!")
                        do {
                            print("🔄 [3D_Engine] Convertendo USDZ para OBJ via ModelIO...")
                            let asset = MDLAsset(url: usdzUrl)
                            try asset.export(to: outputUrl)
                            print("✅ [3D_Engine] OBJ gerado com sucesso em: \(outputUrl.path)")
                        } catch {
                            print("❌ [3D_Engine] Falha ao exportar OBJ via ModelIO: \(error)")
                        }
                        DispatchQueue.main.async {
                            if FileManager.default.fileExists(atPath: usdzUrl.path) && FileManager.default.fileExists(atPath: outputUrl.path) {
                                self.usdzFileURL = usdzUrl
                                self.progress = 1.0
                                self.isProcessing = false
                            } else if self.errorMessage == nil {
                                print("❌ [3D_Engine] Arquivos não encontrados no disco após .processingComplete")
                                self.isProcessing = false
                                self.errorMessage = "O processamento falhou. Tente escancear mais áreas do objeto."
                            }
                        }
                    case .requestError(_, let error):
                        print("❌ [3D_Engine] Erro de Photogrammetry: \(error)")
                        DispatchQueue.main.async {
                            self.errorMessage = error.localizedDescription
                        }
                    case .processingCancelled:
                        print("🛑 [3D_Engine] Processamento cancelado pelo sistema.")
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            self.errorMessage = "Cancelado"
                            if let req = bridgeManager.currentRequest {
                                bridgeManager.sendCancelResult(requestId: req.requestId ?? "")
                            }
                        }
                    case .requestProgress(_, let fractionComplete):
                        // print("⏳ [3D_Engine] Progresso nativo: \(fractionComplete)") // Muito spamoso, ocultando local default.
                        DispatchQueue.main.async {
                            self.progress = fractionComplete * 0.8 // Apenas 80% é a photogrammetry, o resto é a conversao JS (+ upload)
                            if let req = bridgeManager.currentRequest {
                                bridgeManager.sendProgress(requestId: req.requestId ?? "", phase: "processing", percent: Int(fractionComplete * 80))
                            }
                        }
                    default:
                        break
                    }
                }
            }
            
            print("🚀 [3D_Engine] Enviando request para processamento 3D...")
            try session.process(requests: [usdzRequest])
            
        } catch {
            print("❌ [3D_Engine] Falha ao iniciar sessão: \(error)")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.errorMessage = "Falha ao iniciar: \(error.localizedDescription)"
            }
        }
    }
    
    private func convertOBJToGLB(objURL: URL, dirURL: URL) {
        print("🔄 [3D_Engine] ════════════════════════════════")
        print("🔄 [3D_Engine] INICIANDO CONVERSÃO OBJ → GLB")
        print("🔄 [3D_Engine] OBJ input: \(objURL.path)")
        print("🔄 [3D_Engine] OBJ existe? \(FileManager.default.fileExists(atPath: objURL.path))")
        let objSize = (try? FileManager.default.attributesOfItem(atPath: objURL.path)[.size] as? Int) ?? 0
        print("🔄 [3D_Engine] OBJ tamanho: \(objSize / 1024)KB")
        print("🔄 [3D_Engine] Dir: \(dirURL.path)")
        // Encontrar o arquivo MTL (usualmente criado com o mesmo nome .mtl ou material.mtl)
        var mtlPath: String? = nil
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) {
            print("🔄 [3D_Engine] Arquivos no diretório: \(files)")
            if let mtlFile = files.first(where: { $0.hasSuffix(".mtl") }) {
                mtlPath = "/Scans/Models/\(dirURL.lastPathComponent)/\(mtlFile)"
                print("🔄 [3D_Engine] MTL encontrado: \(mtlFile)")
            } else {
                print("🔄 [3D_Engine] ⚠️ Nenhum arquivo MTL encontrado")
            }
        } else {
            print("🔄 [3D_Engine] ❌ Falha ao listar conteúdo do diretório")
        }
        
        // Usar o nome real do arquivo OBJ (pode ser scan.obj ou scan_cropped.obj)
        let objFileName = objURL.lastPathComponent
        let objLocalPath = "/Scans/Models/\(dirURL.lastPathComponent)/\(objFileName)"
        let basePath = "/Scans/Models/\(dirURL.lastPathComponent)"
        print("🔄 [3D_Engine] objLocalPath (para WebKit): \(objLocalPath)")
        print("🔄 [3D_Engine] mtlPath: \(mtlPath ?? "nil")")
        print("🔄 [3D_Engine] basePath: \(basePath)")
        
        self.isProcessing = true
        self.progress = 0.85
        
        if let req = bridgeManager.currentRequest {
            bridgeManager.sendProgress(requestId: req.requestId ?? "", phase: "converting", percent: 85)
        }
        
        print("🔄 [3D_Engine] Chamando converterEngine.convert()...")
        converterEngine.convert(objLocalPath: objLocalPath, mtlLocalPath: mtlPath, basePath: basePath) { glbURL, error in
            DispatchQueue.main.async {
                self.isProcessing = false
                if let err = error {
                    print("❌ [3D_Engine] Conversão GLB FALHOU: \(err)")
                    print("❌ [3D_Engine] Erro detalhado: \(err.localizedDescription)")
                    self.errorMessage = "Erro de conversão GLB: \(err.localizedDescription)"
                } else if let glb = glbURL {
                    let glbSize = (try? FileManager.default.attributesOfItem(atPath: glb.path)[.size] as? Int) ?? 0
                    print("✅ [3D_Engine] Conversão GLB SUCESSO!")
                    print("✅ [3D_Engine] GLB path: \(glb.path)")
                    print("✅ [3D_Engine] GLB tamanho: \(glbSize / 1024)KB")
                    self.glbFileURL = glb
                    self.startUpload(modelFileURL: glb)
                } else {
                    print("❌ [3D_Engine] Conversão retornou nil para URL e nil para erro!")
                    self.errorMessage = "Erro desconhecido na conversão GLB"
                }
            }
        }
    }
    
    private func handleConfirmAndUpload() {
        print("📲 [ReconstructionView] ════════════════════════")
        print("📲 [ReconstructionView] BOTÃO 'Processar e Enviar' CLICADO")
        print("📲 [ReconstructionView] usdzFileURL: \(usdzFileURL?.path ?? "nil")")
        
        guard let dir = usdzFileURL?.deletingLastPathComponent(),
              let obj = usdzFileURL?.deletingLastPathComponent().appendingPathComponent("scan.obj") else {
            print("📲 [ReconstructionView] ❌ GUARD falhou: usdzFileURL é nil ou não tem diretório pai")
            return
        }
        
        print("📲 [ReconstructionView] OBJ path: \(obj.path)")
        print("📲 [ReconstructionView] OBJ existe? \(FileManager.default.fileExists(atPath: obj.path))")
        print("📲 [ReconstructionView] Dir: \(dir.path)")
        
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            print("📲 [ReconstructionView] Arquivos no dir: \(files)")
        }
        
        self.isProcessing = true
        self.progress = 0.5
        if let req = bridgeManager.currentRequest {
            print("📲 [ReconstructionView] requestId: \(req.requestId ?? "nil")")
            bridgeManager.sendProgress(requestId: req.requestId ?? "", phase: "cropping", percent: 50)
        } else {
            print("📲 [ReconstructionView] ⚠️ bridgeManager.currentRequest é nil (modo offline?)")
        }
        
        print("📲 [ReconstructionView] Chamando ModelCropper.processAndCrop()...")
        ModelCropper.processAndCrop(originalObjURL: obj) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let croppedObjURL):
                    print("📲 [ReconstructionView] ✅ ModelCropper retornou SUCESSO")
                    print("📲 [ReconstructionView] Arquivo recortado: \(croppedObjURL.path)")
                    print("📲 [ReconstructionView] Arquivo existe? \(FileManager.default.fileExists(atPath: croppedObjURL.path))")
                    self.convertOBJToGLB(objURL: croppedObjURL, dirURL: dir)
                case .failure(let error):
                    print("📲 [ReconstructionView] ❌ ModelCropper retornou FALHA")
                    print("📲 [ReconstructionView] Erro: \(error)")
                    print("📲 [ReconstructionView] LocalizedDescription: \(error.localizedDescription)")
                    self.errorMessage = "Falha ao recortar modelo: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func startUpload(modelFileURL: URL) {
        guard let payload = bridgeManager.currentRequest else {
            print("⚠️ [3D_Engine] startUpload abortado: Não há um currentRequest ativo.")
            DispatchQueue.main.async {
                self.errorMessage = "Processamento offline finalizado. O modelo foi recortado mas não foi enviado pois o app não foi aberto via web."
            }
            return
        }
        
        print("☁️ [3D_Engine] Iniciando Upload para o Supabase (ProjectID)...")
        isUploading = true
        progress = 0.0
        
        Task {
            do {
                let (projectId, downloadUrl) = try await ModelUploader.uploadAndCreateProject(
                    modelFileURL: modelFileURL,
                    payload: payload
                ) { progressVal in
                    DispatchQueue.main.async {
                        self.progress = Double(progressVal) / 100.0
                        bridgeManager.sendProgress(requestId: payload.requestId ?? "", phase: "uploading", percent: progressVal)
                    }
                }
                
                DispatchQueue.main.async {
                    print("✅ [3D_Engine] Upload concluído! URL Pública: \(downloadUrl)")
                    self.isUploading = false
                    bridgeManager.sendSuccessResult(requestId: payload.requestId ?? "", projectId: projectId, modelUrl: downloadUrl)
                    // Fecha tela automaticamente
                    bridgeManager.isScanning = false
                    dismiss()
                }
            } catch {
                print("❌ [3D_Engine] Falha no Upload Supabase: \(error)")
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorMessage = "Falha no Upload: \(error.localizedDescription)"
                }
            }
        }
    }
}
