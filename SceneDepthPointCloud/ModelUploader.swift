import Foundation
import UIKit

@available(iOS 17.0, *)
class ModelUploader {
    
    enum UploadError: Error {
        case fileNotFound
        case fileReadError
        case networkError(String)
        case invalidResponse
        case serverError(Int)
        case invalidURL
    }
    
    /// Faz o upload do arquivo e insere no banco REST. 
    /// Retorna (projectId, downloadUrl)
    static func uploadAndCreateProject(
        modelFileURL: URL,
        payload: ScanRequestPayload,
        progressHandler: @escaping (Int) -> Void
    ) async throws -> (String, String) {
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelFileURL.path) else {
            throw UploadError.fileNotFound
        }
        
        let fileData: Data
        do {
            fileData = try Data(contentsOf: modelFileURL)
        } catch {
            throw UploadError.fileReadError
        }
        
        // --- 1. UPLOAD PARA O STORAGE ---
        let timestamp = Int(Date().timeIntervalSince1970)
        let patientId = payload.patientId ?? "avulso"
        
        // O Transformador JS nos garante um arquivo binário `.glb`.
        let storagePath = "storage/v1/object/models-3d/\(patientId)/\(timestamp).glb"
        
        var uploadURLString = payload.supabaseUrl ?? ""
        if uploadURLString.isEmpty { throw UploadError.invalidURL }
        if uploadURLString.hasSuffix("/") { uploadURLString.removeLast() }
        
        guard let uploadURL = URL(string: "\(uploadURLString)/\(storagePath)") else {
            throw UploadError.invalidURL
        }
        
        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("Bearer \(payload.supabaseAccessToken ?? "")", forHTTPHeaderField: "Authorization")
        uploadReq.setValue(payload.supabaseAnonKey ?? "", forHTTPHeaderField: "apikey")
        uploadReq.setValue("model/gltf-binary", forHTTPHeaderField: "Content-Type")
        // No supabase v1, storage upload needs a pure binary body for standard POSTs onto the object path
        uploadReq.httpBody = fileData
        
        progressHandler(10) // Uploading init
        print("[Supabase] Realizando upload de \(fileData.count) bytes...")
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 300
        let heavySession = URLSession(configuration: sessionConfig)
        
        // Custom robust async send for massive payload
        let (data, response) = try await heavySession.data(for: uploadReq)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        if !(defaultExpectedRange ~= httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Erro desconhecido"
            print("Storage Erro \(httpResponse.statusCode): \(errorMsg)")
            throw UploadError.networkError("Falha no upload: HTTP \(httpResponse.statusCode)")
        }
        
        progressHandler(80) // Upload done
        
        // --- 2. INSERT NO REST DB ---
        let publicModelURL = "\(uploadURLString)/storage/v1/object/public/models-3d/\(patientId)/\(timestamp).glb"
        
        guard let insertURL = URL(string: "\(uploadURLString)/rest/v1/simulation_projects") else {
            throw UploadError.invalidURL
        }
        
        var insertReq = URLRequest(url: insertURL)
        insertReq.httpMethod = "POST"
        insertReq.setValue("Bearer \(payload.supabaseAccessToken ?? "")", forHTTPHeaderField: "Authorization")
        insertReq.setValue(payload.supabaseAnonKey ?? "", forHTTPHeaderField: "apikey")
        insertReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        insertReq.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        // Decoding the JWT to get user ID, fallback to basic if not easily decoded.
        // O JWT payload tem formato 'header.payload.signature'. O payload eh base64.
        let userId = decodeJWTOptionalId(jwt: payload.supabaseAccessToken ?? "") ?? "user"
        
        let insertBody: [String: Any] = [
            "patient_id": patientId,
            "clinic_id": payload.clinicId ?? "avulso",
            "title": payload.title ?? "Scan 3D - \(Date().formatted(date: .abbreviated, time: .shortened))",
            "base_image_url": publicModelURL,
            "simulation_type": "3D", // Conforme contrato do Web Developer
            "created_by": userId
        ]
        
        insertReq.httpBody = try? JSONSerialization.data(withJSONObject: insertBody)
        
        print("[Supabase] Inserindo no DB REST...")
        let (insertData, insertResponse) = try await URLSession.shared.data(for: insertReq)
        
        guard let insertHttpRes = insertResponse as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        if !(defaultExpectedRange ~= insertHttpRes.statusCode) {
            let errorMsg = String(data: insertData, encoding: .utf8) ?? ""
            print("REST Erro \(insertHttpRes.statusCode): \(errorMsg)")
            throw UploadError.networkError("Falha na Inserção BD: HTTP \(insertHttpRes.statusCode)")
        }
        
        // extrair o id
        let idParsed: String
        if let items = try? JSONSerialization.jsonObject(with: insertData) as? [[String: Any]],
           let firstItem = items.first,
           let projectId = firstItem["id"] as? String {
            idParsed = projectId
        } else {
            idParsed = "new-project"
        }
        
        // --- 3. NOTIFICAR O SUPABASE EDGE FUNCTION ---
        if let token = payload.supabaseAccessToken,
           let anonKey = payload.supabaseAnonKey,
           !uploadURLString.isEmpty,
           idParsed != "new-project" {
            // Roda de forma assíncrona, para não travar a finalização caso a trigger falhe
            Task {
                do {
                    try await NotificationService.dispatchNotification(
                        supabaseUrl: uploadURLString,
                        supabaseAccessToken: token,
                        supabaseAnonKey: anonKey,
                        eventKey: "simulation.shared",
                        sourceTable: "simulation_projects",
                        sourceId: idParsed,
                        clinicId: payload.clinicId ?? "avulso",
                        triggeredByUserId: userId,
                        patientName: payload.patientName,
                        patientId: patientId
                    )
                } catch {
                    print("[NotificationService] Erro ao disparar push notification: \(error)")
                }
            }
        }
        
        progressHandler(100)
        return (idParsed, publicModelURL)
    }
    
    // helper variables
    private static let defaultExpectedRange = 200...299
    
    private static func decodeJWTOptionalId(jwt: String) -> String? {
        let segments = jwt.components(separatedBy: ".")
        if segments.count > 1 {
            var base64Str = segments[1]
            // Base64Url to Base64
            base64Str = base64Str.replacingOccurrences(of: "-", with: "+")
            base64Str = base64Str.replacingOccurrences(of: "_", with: "/")
            let padLength = (4 - base64Str.count % 4) % 4
            base64Str += String(repeating: "=", count: padLength)
            
            if let data = Data(base64Encoded: base64Str),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sub = json["sub"] as? String {
                return sub
            }
        }
        return nil
    }
}
