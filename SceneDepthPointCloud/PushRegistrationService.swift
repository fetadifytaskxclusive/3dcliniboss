import Foundation
import UIKit

@available(iOS 17.0, *)
class PushRegistrationService {
    
    enum RegistrationError: Error {
        case invalidURL
        case networkError(String)
        case invalidResponse
    }
    
    /// Estágio Único: Registro direto via Session Token (Logou e Pronto)
    /// Este método faz o upsert na tabela device_push_tokens seguindo o manual técnico.
    static func updateToken(token: String, accessToken: String) async {
        // Para Upsert em colunas específicas, o PostgREST exige on_conflict na Query String
        let urlString = "\(AppConfig.supabaseURL)/rest/v1/device_push_tokens?on_conflict=user_id,token"
        guard let url = URL(string: urlString) else { return }
        
        let userId = decodeJWTOptionalId(jwt: accessToken) ?? "unknown"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Upsert na tabela: Instrução de resolução de conflito
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        let body: [String: Any] = [
            "user_id": userId,
            "token": token,
            "platform": "ios",
            "bundle_id": "com.cliniboss.app",
            "environment": "sandbox", // Usar 'sandbox' para debug e 'production' para release
            "is_active": true,
            "last_used_at": ISO8601DateFormatter().string(from: Date()),
            "device_name": UIDevice.current.name
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Envia requisição sem logar payload
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success
                } else {
                    if let resStr = String(data: data, encoding: .utf8) {
                        // Backend validation failure
                    }
                }
            }
        } catch {
            // Network error
        }
    }
    
    private static func decodeJWTOptionalId(jwt: String) -> String? {
        let segments = jwt.components(separatedBy: ".")
        if segments.count > 1 {
            var base64Str = segments[1]
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
