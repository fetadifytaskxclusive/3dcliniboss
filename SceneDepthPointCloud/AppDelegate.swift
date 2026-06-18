import Foundation
import UIKit
import UserNotifications

@available(iOS 17.0, *)
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIApplication.shared.applicationIconBadgeNumber = 0
        // Solicita autorização de notificações
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Re-confirma o registro de notificações toda vez que o app abre
        application.registerForRemoteNotifications()
        
        // Se ja tivermos token e sessão salva, tentamos um refresh silencioso no banco
        if let token = PushNotificationManager.shared.apnsToken,
           let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") {
            Task {
                await PushRegistrationService.updateToken(token: token, accessToken: accessToken)
            }
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        // Envia o token para o bridge de forma assíncrona
        DispatchQueue.main.async {
            PushNotificationManager.shared.apnsToken = token
            PushNotificationManager.shared.flushTokenToWebView()
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Silently handle failure
    }
    
    // Mostra notificação se o app estiver em foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    // Lida com o clique na notificação (Deep Linking)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        // Tenta extrair a URL ou Path do payload
        if let path = userInfo["screen"] as? String {
            PushNotificationManager.shared.pendingNavigationPath = path
            PushNotificationManager.shared.triggerNavigation()
        } else if let url = userInfo["url"] as? String {
            PushNotificationManager.shared.pendingNavigationPath = url
            PushNotificationManager.shared.triggerNavigation()
        }
        
        completionHandler()
    }
}

class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var apnsToken: String? = nil
    var notifyWebViewBlock: ((String) -> Void)? = nil
    
    // Deep Linking
    var pendingNavigationPath: String? = nil
    var navigateWebViewBlock: ((String) -> Void)? = nil
    
    func flushTokenToWebView() {
        if let token = apnsToken, let block = notifyWebViewBlock {
            block(token)
        }
    }
    
    func triggerNavigation() {
        if let path = pendingNavigationPath, let block = navigateWebViewBlock {
            block(path)
            pendingNavigationPath = nil
        }
    }
}
