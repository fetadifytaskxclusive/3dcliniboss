import SwiftUI

@available(iOS 17.0, *)
struct HomeView: View {
    @EnvironmentObject var bridgeManager: WebBridgeManager
    
    // MODO TESTE (Altere para false antes de lançar para voltar ao login web)
    @State private var devModeBypass = true
    
    var body: some View {
        if devModeBypass {
            // MODO DE TESTE RÁPIDO DO SCANNER
            ScanSelectionView()
        } else {
            // MODO WEB ORIGINAL (CliniBoss WebView)
            ZStack {
                bridgeManager.topThemeColor
                    .ignoresSafeArea(edges: .top)
                    
                VStack(spacing: 0) {
                    WebViewContainer(url: AppConfig.webAppURL)
                }
            }
            .fullScreenCover(isPresented: $bridgeManager.isScanning) {
                ScanSelectionView()
            }
            .preferredColorScheme(bridgeManager.isDarkBackground ? .dark : .light)
        }
    }
}
