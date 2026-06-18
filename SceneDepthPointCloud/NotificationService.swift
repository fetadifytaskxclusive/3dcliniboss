import Foundation

@available(iOS 17.0, *)
class NotificationService {
    
    enum NotificationError: Error {
        case invalidURL
        case networkError(String)
        case invalidResponse
    }
    
    static func dispatchNotification(
        supabaseUrl: String,
        supabaseAccessToken: String,
        supabaseAnonKey: String,
        eventKey: String,
        sourceTable: String,
        sourceId: String,
        clinicId: String,
        triggeredByUserId: String,
        patientName: String?,
        patientId: String?
    ) async throws {
        
        var baseUrl = supabaseUrl
        if baseUrl.hasSuffix("/") {
            baseUrl.removeLast()
        }
        
        guard let url = URL(string: "\(baseUrl)/functions/v1/notification-orchestrator") else {
            throw NotificationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(supabaseAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Se a function exigir anon key
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        // Define dict for patient context
        var patientContext: [String: Any] = [:]
        if let pid = patientId {
            patientContext["id"] = pid
        }
        if let pname = patientName {
            patientContext["first_name"] = pname
            patientContext["full_name"] = pname
        }
        
        let body: [String: Any] = [
            "event_key": eventKey,
            "source_table": sourceTable,
            "source_id": sourceId,
            "clinic_id": clinicId,
            "triggered_by": triggeredByUserId,
            "context": [
                "patient": patientContext,
                "current_user": [
                    "id": triggeredByUserId
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("[NotificationService] Disparando Edge Function \(eventKey)...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationError.invalidResponse
        }
        
        let resStr = String(data: data, encoding: .utf8) ?? ""
        print("[NotificationService] Response \(httpResponse.statusCode): \(resStr)")
        
        if !(200...299 ~= httpResponse.statusCode) {
             throw NotificationError.networkError("HTTP Error \(httpResponse.statusCode): \(resStr)")
        }
    }
}
