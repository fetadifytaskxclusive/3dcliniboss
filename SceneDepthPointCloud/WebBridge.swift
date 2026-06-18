import SwiftUI
import WebKit

struct ScanRequestPayload: Decodable {
    let action: String?
    let requestId: String?
    let patientId: String?
    let clinicId: String?
    let patientName: String?
    let title: String?
    let supabaseAccessToken: String?
    let supabaseRefreshToken: String?
    let supabaseUrl: String?
    let supabaseAnonKey: String?
    let scanType: String? // "head" or "body" opcional
}

@MainActor
class WebBridgeManager: ObservableObject {
    @Published var isScanning = false
    @Published var currentRequest: ScanRequestPayload? = nil
    @Published var topThemeColor: Color = Color(red: 0.0, green: 0.81, blue: 0.82)
    @Published var isDarkBackground: Bool = false
    
    // Referencia para o webview pra injetar JS
    weak var webView: WKWebView?
    
    func sendSuccessResult(requestId: String, projectId: String, modelUrl: String) {
        let jsonString = """
        {
          "requestId": "\(requestId)",
          "status": "success",
          "projectId": "\(projectId)",
          "modelUrl": "\(modelUrl)"
        }
        """
        dispatchEvent(jsonString: jsonString)
    }
    
    func sendCancelResult(requestId: String) {
        let jsonString = """
        {
          "requestId": "\(requestId)",
          "status": "cancelled"
        }
        """
        dispatchEvent(jsonString: jsonString)
    }
    
    func sendErrorResult(requestId: String, errorCode: String, errorMessage: String) {
        let safeError = errorMessage.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
        let jsonString = """
        {
          "requestId": "\(requestId)",
          "status": "error",
          "errorCode": "\(errorCode)",
          "errorMessage": "\(safeError)"
        }
        """
        dispatchEvent(jsonString: jsonString)
    }
    
    func sendProgress(requestId: String, phase: String, percent: Int) {
        // scanner3D:progress
        let jsonString = """
        {
          "requestId": "\(requestId)",
          "phase": "\(phase)",
          "percent": \(percent)
        }
        """
        let js = """
          console.log('🚀 [JS Bridge] Enviando progresso:', \(jsonString));
          window.dispatchEvent(new CustomEvent('scanner3D:progress', {
            detail: \(jsonString)
          }));
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    private func dispatchEvent(jsonString: String) {
        let js = """
          console.log('🚀 [JS Bridge] Disparando evento scanner3D:result:', \(jsonString));
          window.dispatchEvent(new CustomEvent('scanner3D:result', {
            detail: \(jsonString)
          }));
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("Error evaluating JS: \(error)")
                }
            }
        }
    }
    
    func injectAPNSToken(token: String) {
        let js = """
          window.dispatchEvent(new CustomEvent('native:pushToken', {
            detail: { token: '\(token)', platform: 'ios' }
          }));
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func navigateTo(url: String) {
        guard let webView = self.webView else { return }
        
        let js: String
        if url.hasPrefix("http") {
            js = "window.location.href = '\(url)';"
        } else {
            // Assume it's a path like /profile
            js = "window.location.pathname = '\(url)';"
        }
        
        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

class WebViewProcessPoolShare {
    static let shared = WKProcessPool()
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @EnvironmentObject var bridgeManager: WebBridgeManager
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Injeta o pool compartilhado para persistência de sessão
        config.processPool = WebViewProcessPoolShare.shared
        
        // Garante que os Cookies e LocalStorage fiquem salvos
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let userContentController = WKUserContentController()
        
        // Script para capturar Console.Log da Web
        let consoleJS = """
        var originalLog = console.log;
        console.log = function() {
            var msgs = Array.from(arguments).join(' ');
            window.webkit.messageHandlers.consoleHandler.postMessage('[LOG] ' + msgs);
            originalLog.apply(console, arguments);
        };
        var originalErr = console.error;
        console.error = function() {
            var msgs = Array.from(arguments).join(' ');
            window.webkit.messageHandlers.consoleHandler.postMessage('[ERROR] ' + msgs);
            originalErr.apply(console, arguments);
        };
        window.onerror = function(msg, url, line) {
            window.webkit.messageHandlers.consoleHandler.postMessage('[WINDOW_ERROR] ' + msg + ' at ' + line);
        };
        """
        let consoleScript = WKUserScript(source: consoleJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(consoleScript)
        userContentController.add(context.coordinator, name: "consoleHandler")
        
        userContentController.add(context.coordinator, name: "scanner3D")
        
        let sessionJS = """
        (function() {
            function checkSession() {
                try {
                    // LOG DE DEBUG: Listar chaves para encontrarmos a correta
                    var keys = [];
                    for (var i = 0; i < localStorage.length; i++) {
                        keys.push(localStorage.key(i));
                    }

                    var projectRef = "\(AppConfig.supabaseProjectID)";
                    var sessionKey = "cliniboss-auth"; // Chave identificada nos logs
                    var rawData = localStorage.getItem(sessionKey);
                    
                    // Se não achou pela chave cliniboss-auth, tenta busca por qualquer chave que contenha 'auth'
                    if (!rawData) {
                        var genericKey = keys.find(k => k.toLowerCase().includes("auth"));
                        if (genericKey) {
                            rawData = localStorage.getItem(genericKey);
                        }
                    }

                    if (rawData) {
                        var data = JSON.parse(rawData);
                        // Suporte para estrutura Supabase (Session ou User)
                        var accessToken = data.access_token || (data.session ? data.session.access_token : null);
                        
                        if (accessToken) {
                            window.webkit.messageHandlers.sessionSync.postMessage({
                                accessToken: accessToken
                            });
                        }
                    }
                } catch(e) {
                }
            }
            setInterval(checkSession, 5000);
            checkSession();
        })();
        """
        let sessionScript = WKUserScript(source: sessionJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(sessionScript)
        userContentController.add(context.coordinator, name: "sessionSync")
        
        config.userContentController = userContentController
        
        // Ativando midia para autoplay (se necessario no site)
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true // Permite usar o Safari DevTools do Mac no app compilado!
        }
#endif
        
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        // Adiciona Pull to Refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.refreshWebView(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        // Define o custom user agent para a deteccao do site
        webView.evaluateJavaScript("navigator.userAgent") { (result, error) in
            if let defaultUA = result as? String {
                webView.customUserAgent = "\(defaultUA) CliniBoss3DScanner/1.0"
            } else {
                webView.customUserAgent = "CliniBoss3DScanner/1.0"
            }
        }
        
        // Armazena no manager para uso futuro (injetar eventos de volta)
        bridgeManager.webView = webView
        
        // Registra bloco de envio de push token
        PushNotificationManager.shared.notifyWebViewBlock = { token in
            bridgeManager.injectAPNSToken(token: token)
        }
        
        // Registra bloco de navegação (Deep Linking)
        PushNotificationManager.shared.navigateWebViewBlock = { path in
            bridgeManager.navigateTo(url: path)
        }
        
        // Se ja tivermos o token, injeta imediatamente
        PushNotificationManager.shared.flushTokenToWebView()
        PushNotificationManager.shared.triggerNavigation()
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Nada dinamico aqui para atualizacoes de view normais do SwiftUI
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate, WKUIDelegate {
        var parent: WebViewContainer
        var timer: Timer?
        var isFetchingColor = false
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
            super.init()
            self.startColorTimer()
        }
        
        @objc func refreshWebView(_ sender: UIRefreshControl) {
            parent.bridgeManager.webView?.reload()
            sender.endRefreshing()
        }
        
        func startColorTimer() {
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.fetchTopColor()
            }
        }
        
        func fetchTopColor() {
            guard let webView = parent.bridgeManager.webView, !isFetchingColor else { return }
            isFetchingColor = true
            
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: webView.bounds.width / 2, y: 1, width: 1, height: 1)
            
            webView.takeSnapshot(with: config) { [weak self] image, error in
                self?.isFetchingColor = false
                guard let self = self, let img = image, let colorData = img.topCenterPixelData else { return }
                
                DispatchQueue.main.async {
                    let newColor = Color(red: colorData.r, green: colorData.g, blue: colorData.b)
                    if self.parent.bridgeManager.topThemeColor != newColor {
                        self.parent.bridgeManager.topThemeColor = newColor
                        self.parent.bridgeManager.isDarkBackground = colorData.isDarkLuminance
                    }
                }
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Se rolar muito rápido, o relógio também atualiza nativamente
            fetchTopColor()
        }
        
        // Recebe mensagens enviadas do window.webkit.messageHandlers.scanner3D.postMessage
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "consoleHandler" {
                if let logStr = message.body as? String {
                    print("🌐 [Web] \(logStr)")
                }
                return
            }
            
            if message.name == "scanner3D" {
                guard let body = message.body as? [String: Any] else {
                    print("⚠️ [3D_Scanner] Erro: O corpo do postMessage não é um objeto JSON válido!")
                    return
                }
                
                print("=========================================")
                print("📲 [3D_Scanner] Comando Recebido! Payload: \(body.keys)")
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
                    let payload = try JSONDecoder().decode(ScanRequestPayload.self, from: jsonData)
                    
                    if payload.action == "startScan" {
                        print("📸 [3D_Scanner] Ação 'startScan' reconhecida! Iniciando câmera LiDAR...")
                        
                        // --- ATUALIZAÇÃO SILENCIOSA DE PUSH TOKEN ---
                        if let token = PushNotificationManager.shared.apnsToken,
                           let accessToken = payload.supabaseAccessToken {
                            Task {
                                await PushRegistrationService.updateToken(token: token, accessToken: accessToken)
                            }
                        }
                        
                        DispatchQueue.main.async {
                            self.parent.bridgeManager.currentRequest = payload
                            self.parent.bridgeManager.isScanning = true
                        }
                    } else {
                        print("ℹ️ [3D_Scanner] Comando \(payload.action ?? "desconhecido") ignorado.")
                    }
                } catch {
                    print("❌ [3D_Scanner] ERRO FATAL DE DECODING JSON: \(error)")
                }
            } else if message.name == "sessionSync" {
                guard let body = message.body as? [String: Any],
                      let token = PushNotificationManager.shared.apnsToken,
                      let accessToken = body["accessToken"] as? String else { 
                    return 
                }
                UserDefaults.standard.set(accessToken, forKey: "supabase_access_token")
                Task {
                    await PushRegistrationService.updateToken(token: token, accessToken: accessToken)
                }
            }
        }
        
        // Permite visualizar alert() vindo do Javascript
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "Aviso do Site", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() }))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                rootVC.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }
    }
}

extension UIImage {
    var topCenterPixelData: (r: Double, g: Double, b: Double, isDarkLuminance: Bool)? {
        guard let cgImage = self.cgImage else { return nil }
        
        let width = 1
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData: [UInt8] = [0, 0, 0, 0]
        
        guard let context = CGContext(data: &pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let r = Double(pixelData[0]) / 255.0
        let g = Double(pixelData[1]) / 255.0
        let b = Double(pixelData[2]) / 255.0
        
        // ITU-R BT.709 Luminance Formula
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        
        return (r, g, b, luma < 0.5)
    }
}
