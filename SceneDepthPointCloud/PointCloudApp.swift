import SwiftUI
import RealityKit

@main
@available(iOS 17.0, *)
struct PointCloudApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var sessionManager = ScannerSessionManager()
    @StateObject private var bridgeManager = WebBridgeManager()
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            HomeView()
                .environmentObject(sessionManager)
                .environmentObject(bridgeManager)
                .preferredColorScheme(.light)
        }
    }
}
