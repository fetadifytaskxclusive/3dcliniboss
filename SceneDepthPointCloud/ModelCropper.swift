import Foundation
import SceneKit
import SceneKit.ModelIO
import Vision
import ModelIO
import Metal

@available(iOS 17.0, *)
class ModelCropper {
    
    enum CropperError: Error, LocalizedError {
        case failedToLoadModel
        case faceNotFound
        case snapshotFailed
        case processingFailed(String)
        case objParsingFailed
        
        var errorDescription: String? {
            switch self {
            case .failedToLoadModel: return "Não foi possível carregar o modelo 3D."
            case .faceNotFound: return "Não foi possível detectar o rosto do paciente após a varredura multi-ângulo. Garanta iluminação uniforme e boa cobertura do enquadramento facial no escaneamento."
            case .snapshotFailed: return "Falha ao renderizar snapshot do modelo."
            case .processingFailed(let msg): return "Falha no processamento: \(msg)"
            case .objParsingFailed: return "Falha ao analisar o arquivo OBJ."
            }
        }
    }
    
    // Margin below the chin to include the neck (as a ratio of the face bounding box height)
    private static let neckMarginRatio: Float = 0.35
    
    // Snapshot size for Vision analysis
    private static let snapshotSize = CGSize(width: 1024, height: 1024)
    
    /// Main pipeline: loads OBJ → takes snapshot → detects face → crops → saves new OBJ
    static func processAndCrop(originalObjURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        
        print("✂️ [ModelCropper] ════════════════════════════════════════")
        print("✂️ [ModelCropper] INICIANDO PIPELINE DE RECORTE AUTOMÁTICO")
        print("✂️ [ModelCropper] ════════════════════════════════════════")
        print("✂️ [ModelCropper] Arquivo de entrada: \(originalObjURL.path)")
        print("✂️ [ModelCropper] Arquivo existe? \(FileManager.default.fileExists(atPath: originalObjURL.path))")
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: originalObjURL.path)[.size] as? Int) ?? 0
        print("✂️ [ModelCropper] Tamanho do arquivo de entrada: \(fileSize / 1024)KB")
        print("✂️ [ModelCropper] neckMarginRatio: \(neckMarginRatio)")
        print("✂️ [ModelCropper] snapshotSize: \(snapshotSize)")
        
        Task {
            let pipelineStart = Date()
            print("✂️ [ModelCropper] Task de background iniciada.")
            do {
                // ═══════════════════════════════════════════════════════
                // STEP 1: Load OBJ model into SCNScene
                // ═══════════════════════════════════════════════════════
                print("✂️ [ModelCropper] [PASSO 1/5] Carregando modelo OBJ em SCNScene...")
                let step1Start = Date()
                let usdzURL = originalObjURL.deletingPathExtension().appendingPathExtension("usdz")
                let scene = try loadModelIntoScene(usdzURL: usdzURL)
                let step1Duration = Date().timeIntervalSince(step1Start)
                let boundingBox = scene.rootNode.boundingBox
                let modelMinY = boundingBox.min.y
                let modelMaxY = boundingBox.max.y
                let modelHeight = modelMaxY - modelMinY
                let modelMinX = boundingBox.min.x, modelMaxX = boundingBox.max.x
                let modelMinZ = boundingBox.min.z, modelMaxZ = boundingBox.max.z
                print("✂️ [ModelCropper] [PASSO 1/5] ✅ Concluído em \(String(format: "%.2f", step1Duration))s")
                print("✂️ [ModelCropper] BoundingBox X: [\(modelMinX) ... \(modelMaxX)]")
                print("✂️ [ModelCropper] BoundingBox Y: [\(modelMinY) ... \(modelMaxY)] (altura: \(modelHeight))")
                print("✂️ [ModelCropper] BoundingBox Z: [\(modelMinZ) ... \(modelMaxZ)]")
                print("✂️ [ModelCropper] Nós filhos na cena: \(scene.rootNode.childNodes.count)")
                
                // ═══════════════════════════════════════════════════════
                // STEP 2 & 3: Render and Detect Face with Multi-Angle Fallback
                // ═══════════════════════════════════════════════════════
                print("✂️ [ModelCropper] [PASSO 2/3] Tentando detectar rosto com varredura multi-ângulo...")
                
                // Angles in radians: Frontal, yaw left 15°, yaw right 15°, pitch down 10°
                let angles: [(yaw: Float, pitch: Float)] = [
                    (0.0, 0.0),
                    (-15.0 * .pi / 180.0, 0.0),
                    (15.0 * .pi / 180.0, 0.0),
                    (0.0, -10.0 * .pi / 180.0)
                ]
                
                var cutYNormalized: CGFloat? = nil
                
                for (index, angle) in angles.enumerated() {
                    print("✂️ [ModelCropper] Tentando ângulo \(index + 1)/\(angles.count): yaw=\(angle.yaw * 180 / .pi)°, pitch=\(angle.pitch * 180 / .pi)°")
                    
                    guard let snapshot = renderFrontalSnapshot(scene: scene, yaw: angle.yaw, pitch: angle.pitch) else {
                        print("✂️ [ModelCropper] ⚠️ Falha ao gerar snapshot para ângulo \(index + 1)")
                        continue
                    }
                    
                    do {
                        let detectedY = try await detectFaceAndComputeCutLine(in: snapshot)
                        print("✂️ [ModelCropper] ✅ Rosto detectado com sucesso no ângulo \(index + 1)!")
                        cutYNormalized = detectedY
                        break
                    } catch {
                        print("✂️ [ModelCropper] ⚠️ Não detectou rosto no ângulo \(index + 1): \(error.localizedDescription)")
                    }
                }
                
                guard let finalCutYNormalized = cutYNormalized else {
                    print("✂️ [ModelCropper] ❌ Falha em todos os ângulos de detecção facial.")
                    throw CropperError.faceNotFound
                }
                
                // ═══════════════════════════════════════════════════════
                // STEP 4: Map 2D coordinate → Y height in the 3D world
                // ═══════════════════════════════════════════════════════
                print("✂️ [ModelCropper] [PASSO 4/5] Mapeando coordenada 2D → 3D...")
                let cutY3D = modelMinY + Float(finalCutYNormalized) * modelHeight
                print("✂️ [ModelCropper] Fórmula: \(modelMinY) + \(Float(finalCutYNormalized)) * \(modelHeight) = \(cutY3D)")
                print("✂️ [ModelCropper] [PASSO 4/5] ✅ Altura de corte 3D: Y = \(cutY3D)")
                
                // ═══════════════════════════════════════════════════════
                // STEP 5: Filter the OBJ file (remove vertices below cutY3D)
                // ═══════════════════════════════════════════════════════
                print("✂️ [ModelCropper] [PASSO 5/5] Filtrando vértices do OBJ...")
                let step5Start = Date()
                let croppedURL = try await filterOBJFile(originalURL: originalObjURL, cutYThreshold: cutY3D)
                let step5Duration = Date().timeIntervalSince(step5Start)
                print("✂️ [ModelCropper] [PASSO 5/5] ✅ Concluído em \(String(format: "%.2f", step5Duration))s")
                let totalDuration = Date().timeIntervalSince(pipelineStart)
                print("✂️ [ModelCropper] ════════════════════════════════════════")
                print("✂️ [ModelCropper] PIPELINE CONCLUÍDO em \(String(format: "%.2f", totalDuration))s")
                print("✂️ [ModelCropper] Arquivo final: \(croppedURL.path)")
                print("✂️ [ModelCropper] ════════════════════════════════════════")
                
                completion(.success(croppedURL))
                
            } catch {
                let totalDuration = Date().timeIntervalSince(pipelineStart)
                print("✂️ [ModelCropper] ❌ ════════════════════════════════════════")
                print("✂️ [ModelCropper] ❌ ERRO NO PIPELINE após \(String(format: "%.2f", totalDuration))s")
                print("✂️ [ModelCropper] ❌ Tipo: \(type(of: error))")
                print("✂️ [ModelCropper] ❌ Descrição: \(error)")
                print("✂️ [ModelCropper] ❌ LocalizedDescription: \(error.localizedDescription)")
                print("✂️ [ModelCropper] ❌ ════════════════════════════════════════")
                print("✂️ [ModelCropper] ⚠️ Propagando erro para a view clínica...")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Step 1: Load OBJ into SCNScene
    
    private static func loadModelIntoScene(usdzURL: URL) throws -> SCNScene {
        print("✂️ [ModelCropper:loadModel] Iniciando carregamento do USDZ...")
        print("✂️ [ModelCropper:loadModel] URL: \(usdzURL.path)")
        
        guard let scene = try? SCNScene(url: usdzURL, options: nil) else {
            print("✂️ [ModelCropper:loadModel] ❌ Falha ao carregar a cena USDZ.")
            throw CropperError.failedToLoadModel
        }
        
        // Place all nodes inside a wrapper to facilitate bounding box calculation
        let wrapperNode = SCNNode()
        let children = Array(scene.rootNode.childNodes)
        for child in children {
            wrapperNode.addChildNode(child)
        }
        scene.rootNode.addChildNode(wrapperNode)
        
        print("✂️ [ModelCropper:loadModel] ✅ Cena montada com texturas originais.")
        return scene
    }
    
    // MARK: - Step 2: Render Frontal Snapshot (Orthographic Camera) with rotation parameters
    
    private static func renderFrontalSnapshot(scene: SCNScene, yaw: Float = 0, pitch: Float = 0) -> UIImage? {
        print("✂️ [ModelCropper:snapshot] Calculando bounding box da cena...")
        let (minBB, maxBB) = scene.rootNode.boundingBox
        let centerX = (minBB.x + maxBB.x) / 2
        let centerY = (minBB.y + maxBB.y) / 2
        let centerZ = (minBB.z + maxBB.z) / 2
        
        let width = maxBB.x - minBB.x
        let height = maxBB.y - minBB.y
        let depth = maxBB.z - minBB.z
        print("✂️ [ModelCropper:snapshot] Centro: (\(centerX), \(centerY), \(centerZ))")
        print("✂️ [ModelCropper:snapshot] Dimensões: W=\(width), H=\(height), D=\(depth)")
        
        // Apply temporary rotation to the model wrapper node for multi-angle snapshot
        let modelNode = scene.rootNode.childNodes.first { $0.camera == nil && $0.light == nil }
        let originalEuler = modelNode?.eulerAngles
        if yaw != 0 || pitch != 0 {
            modelNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
            print("✂️ [ModelCropper:snapshot] Aplicando rotação temporária: pitch=\(pitch), yaw=\(yaw)")
        }
        
        defer {
            // Restore original rotation
            if let original = originalEuler {
                modelNode?.eulerAngles = original
            }
        }
        
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(width, height)) * 0.6
        camera.zNear = 0.01
        camera.zFar = Double(depth * 10 + 100)
        cameraNode.camera = camera
        print("✂️ [ModelCropper:snapshot] Câmera ortográfica: scale=\(camera.orthographicScale), zNear=\(camera.zNear), zFar=\(camera.zFar)")
        
        let camZ = centerZ + depth * 2 + 1
        cameraNode.position = SCNVector3(centerX, centerY, camZ)
        cameraNode.look(at: SCNVector3(centerX, centerY, centerZ))
        scene.rootNode.addChildNode(cameraNode)
        print("✂️ [ModelCropper:snapshot] Posição da câmera: (\(centerX), \(centerY), \(camZ))")
        print("✂️ [ModelCropper:snapshot] Look-at: (\(centerX), \(centerY), \(centerZ))")
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white
        ambientLight.light?.intensity = 300 // Reduced from 1000 to improve shading/depth
        scene.rootNode.addChildNode(ambientLight)
        print("✂️ [ModelCropper:snapshot] Luz ambiente adicionada (intensidade: 300)")
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.color = UIColor.white
        directionalLight.light?.intensity = 900 // Slightly increased from 800 to highlight contours
        // Set slightly angled direction to create soft shadow depth
        directionalLight.position = SCNVector3(centerX + width, centerY + height, camZ)
        directionalLight.look(at: SCNVector3(centerX, centerY, centerZ))
        scene.rootNode.addChildNode(directionalLight)
        print("✂️ [ModelCropper:snapshot] Luz direcional adicionada com inclinação (intensidade: 900)")
        
        print("✂️ [ModelCropper:snapshot] Criando MTLDevice para SCNRenderer...")
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("✂️ [ModelCropper:snapshot] ❌ MTLCreateSystemDefaultDevice() retornou nil!")
            return nil
        }
        
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        scene.background.contents = UIColor.systemGray4 // System Gray 4 for enhanced contrast with skin tones/mesh
        
        print("✂️ [ModelCropper:snapshot] Chamando renderer.snapshot()...")
        let snapshot = renderer.snapshot(
            atTime: 0,
            with: snapshotSize,
            antialiasingMode: .multisampling4X
        )
        
        // Clean up added camera and lights from the scene
        cameraNode.removeFromParentNode()
        ambientLight.removeFromParentNode()
        directionalLight.removeFromParentNode()
        
        print("✂️ [ModelCropper:snapshot] snapshot() retornou: \(snapshot != nil ? "UIImage válida" : "nil")")
        return snapshot
    }
    
    // MARK: - Step 3: Detect Face and Calculate Cut Line (Async/Await)
    
    private static func detectFaceAndComputeCutLine(in image: UIImage) async throws -> CGFloat {
        print("✂️ [ModelCropper:vision] Preparando imagem para análise...")
        guard let cgImage = image.cgImage else {
            print("✂️ [ModelCropper:vision] ❌ image.cgImage retornou nil!")
            throw CropperError.snapshotFailed
        }
        print("✂️ [ModelCropper:vision] CGImage: \(cgImage.width)x\(cgImage.height)")
        
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let landmarksRequest = VNDetectFaceLandmarksRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    let allResults = request.results as? [VNFaceObservation] ?? []
                    print("✂️ [ModelCropper:vision] Rostos encontrados: \(allResults.count)")
                    
                    guard let face = allResults.first else {
                        continuation.resume(throwing: CropperError.faceNotFound)
                        return
                    }
                    
                    let faceBoundingBox = face.boundingBox
                    print("✂️ [ModelCropper:vision] ✅ Face detectada com landmark! Confidence: \(face.confidence)")
                    
                    let chinY = faceBoundingBox.origin.y
                    let faceHeight = faceBoundingBox.size.height
                    let neckMargin = faceHeight * CGFloat(neckMarginRatio)
                    let cutLine = max(0, chinY - neckMargin)
                    
                    continuation.resume(returning: cutLine)
                }
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([landmarksRequest])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            print("✂️ [ModelCropper:vision] Landmarks falhou com erro: \(error.localizedDescription)")
            print("✂️ [ModelCropper:vision] Tentando fallback com VNDetectFaceRectanglesRequest...")
            return try await detectFaceFallback(cgImage: cgImage)
        }
    }
    
    private static func detectFaceFallback(cgImage: CGImage) async throws -> CGFloat {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNFaceObservation],
                      let face = results.first else {
                    continuation.resume(throwing: CropperError.faceNotFound)
                    return
                }
                
                let faceBoundingBox = face.boundingBox
                print("✂️ [ModelCropper:fallback] Face detectada no fallback! Confidence: \(face.confidence)")
                let chinY = faceBoundingBox.origin.y
                let faceHeight = faceBoundingBox.size.height
                let neckMargin = faceHeight * CGFloat(neckMarginRatio)
                let cutLine = max(0, chinY - neckMargin)
                
                continuation.resume(returning: cutLine)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Step 5: Filter the OBJ File (Streaming Parser + Writer)
    
    private static func filterOBJFile(originalURL: URL, cutYThreshold: Float) async throws -> URL {
        print("✂️ [ModelCropper:filter] Lendo arquivo OBJ: \(originalURL.lastPathComponent)")
        
        struct Vertex {
            var x, y, z: Float
        }
        
        struct Face {
            var v1, v2, v3: Int
            var rawParts: [String]
        }
        
        var vertices = [Vertex]()
        var uvs = [String]()
        var normals = [String]()
        var faces = [Face]()
        var materials = [String]()
        
        var maxZ: Float = -9999.0
        
        // 1. Parsing Line by Line (AsyncSequence)
        for try await line in originalURL.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("v ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4, let y = Float(parts[2]), let z = Float(parts[3]) {
                    let x = Float(parts[1])!
                    vertices.append(Vertex(x: x, y: y, z: z))
                    if y >= cutYThreshold {
                        if z > maxZ { maxZ = z }
                    }
                }
            } else if trimmed.hasPrefix("vt ") {
                uvs.append(trimmed)
            } else if trimmed.hasPrefix("vn ") {
                normals.append(trimmed)
            } else if trimmed.hasPrefix("f ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    if let v1 = Int(parts[1].components(separatedBy: "/")[0]),
                       let v2 = Int(parts[2].components(separatedBy: "/")[0]),
                       let v3 = Int(parts[3].components(separatedBy: "/")[0]) {
                        faces.append(Face(v1: v1 - 1, v2: v2 - 1, v3: v3 - 1, rawParts: parts))
                    }
                }
            } else if trimmed.hasPrefix("mtllib") || trimmed.hasPrefix("usemtl") {
                materials.append(trimmed)
            }
        }
        
        print("✂️ [ModelCropper:filter] Vertices lidos: \(vertices.count), Faces: \(faces.count)")
        print("✂️ [ModelCropper:filter] Base Y: \(cutYThreshold), Max Z (Nariz): \(maxZ)")
        
        // 2. Slanted Guillotine
        let slope: Float = 0.50
        var keptVertexIndices = Set<Int>()
        var oldToNewMap = [Int: Int]()
        
        for (i, v) in vertices.enumerated() {
            let dz = maxZ - v.z
            let neckY = cutYThreshold + (dz * slope)
            if v.y >= neckY {
                keptVertexIndices.insert(i)
                oldToNewMap[i] = oldToNewMap.count
            }
        }
        
        var keptFaces = [Face]()
        for f in faces {
            if keptVertexIndices.contains(f.v1) && keptVertexIndices.contains(f.v2) && keptVertexIndices.contains(f.v3) {
                keptFaces.append(f)
            }
        }
        
        print("✂️ [ModelCropper:filter] Restaram \(keptVertexIndices.count) vértices e \(keptFaces.count) faces.")
        
        var finalVertices = [Vertex]()
        let sortedOldIndices = oldToNewMap.keys.sorted()
        for oldIdx in sortedOldIndices {
            finalVertices.append(vertices[oldIdx])
        }
        
        // Calculate center (Bounding Box) of cropped vertices to center the pivot
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZVal = -Float.greatestFiniteMagnitude
        for v in finalVertices {
            if v.x < minX { minX = v.x }
            if v.x > maxX { maxX = v.x }
            if v.y < minY { minY = v.y }
            if v.y > maxY { maxY = v.y }
            if v.z < minZ { minZ = v.z }
            if v.z > maxZVal { maxZVal = v.z }
        }
        let cx = (minX + maxX) / 2.0
        let cy = (minY + maxY) / 2.0
        let cz = (minZ + maxZVal) / 2.0
        print("✂️ [ModelCropper:filter] Centro calculado para pivot: (\(cx), \(cy), \(cz))")
        
        let centeredVertices = finalVertices.map { v in
            Vertex(x: v.x - cx, y: v.y - cy, z: v.z - cz)
        }
        
        var newFacesLines = [String]()
        for f in keptFaces {
            let n1 = oldToNewMap[f.v1]! + 1
            let n2 = oldToNewMap[f.v2]! + 1
            let n3 = oldToNewMap[f.v3]! + 1
            
            let uv1 = f.rawParts[1].components(separatedBy: "/").count > 1 ? f.rawParts[1].components(separatedBy: "/")[1] : ""
            let uv2 = f.rawParts[2].components(separatedBy: "/").count > 1 ? f.rawParts[2].components(separatedBy: "/")[1] : ""
            let uv3 = f.rawParts[3].components(separatedBy: "/").count > 1 ? f.rawParts[3].components(separatedBy: "/")[1] : ""
            
            let vn1 = f.rawParts[1].components(separatedBy: "/").count > 2 ? f.rawParts[1].components(separatedBy: "/")[2] : ""
            let vn2 = f.rawParts[2].components(separatedBy: "/").count > 2 ? f.rawParts[2].components(separatedBy: "/")[2] : ""
            let vn3 = f.rawParts[3].components(separatedBy: "/").count > 2 ? f.rawParts[3].components(separatedBy: "/")[2] : ""
            
            if !vn1.isEmpty || !vn2.isEmpty || !vn3.isEmpty {
                newFacesLines.append("f \(n1)/\(uv1)/\(vn1) \(n2)/\(uv2)/\(vn2) \(n3)/\(uv3)/\(vn3)")
            } else {
                newFacesLines.append("f \(n1)/\(uv1) \(n2)/\(uv2) \(n3)/\(uv3)")
            }
        }
        
        // 4. Save the file streaming line-by-line
        let outputDir = originalURL.deletingLastPathComponent()
        let croppedURL = outputDir.appendingPathComponent("scan_cropped.obj")
        
        try? FileManager.default.removeItem(at: croppedURL)
        FileManager.default.createFile(atPath: croppedURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: croppedURL) else {
            throw CropperError.processingFailed("Não foi possível criar o arquivo de saída.")
        }
        defer {
            try? fileHandle.close()
        }
        
        func writeLine(_ line: String) throws {
            if let data = (line + "\n").data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
        }
        
        if materials.count > 0 { try writeLine(materials[0]) }
        for v in centeredVertices { try writeLine("v \(v.x) \(v.y) \(v.z)") }
        for vt in uvs { try writeLine(vt) }
        for vn in normals { try writeLine(vn) }
        if materials.count > 1 { try writeLine(materials[1]) }
        for f in newFacesLines { try writeLine(f) }
        
        print("✅ [ModelCropper:filter] SUCESSO! OBJ Salvo em: \(croppedURL.path)")
        return croppedURL
    }
}
