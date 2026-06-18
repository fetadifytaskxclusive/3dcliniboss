import WebKit
import Foundation

@available(iOS 17.0, *)
class GLBConverterEngine: NSObject, WKScriptMessageHandler {
    
    private var webView: WKWebView!
    private var onComplete: ((URL?, Error?) -> Void)?
    private var isEngineReady = false
    private var pendingTask: (() -> Void)?
    
    private lazy var tempGLBURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let uniqueId = UUID().uuidString
        return documentsPath.appendingPathComponent("Scans/Models/converted-\(uniqueId).glb")
    }()
    
    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(self, name: "converterBridge")
        config.userContentController = userContent
        
        // Registrar app:// scheme
        config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "app")
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        
        // Evita limits memory (opcional)
        if #available(iOS 14.0, *) {
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = prefs
        }
    }
    
    func startEngine() {
        guard let threeData = NSDataAsset(name: "three.min")?.data, let threeJS = String(data: threeData, encoding: .utf8),
              let mtlData = NSDataAsset(name: "MTLLoader")?.data, let mtlJS = String(data: mtlData, encoding: .utf8),
              let objData = NSDataAsset(name: "OBJLoader")?.data, let objJS = String(data: objData, encoding: .utf8),
              let gltfData = NSDataAsset(name: "GLTFExporter")?.data, let gltfJS = String(data: gltfData, encoding: .utf8) else {
            print("❌ [GLBConverterEngine] Falha ao carregar DataAssets JS Offline!")
            return
        }
        
        let htmlSource = """
        <!DOCTYPE html>
        <html>
        <head>
            <script> \(threeJS) </script>
            <script> \(mtlJS) </script>
            <script> \(objJS) </script>
            <script> \(gltfJS) </script>
        </head>
        <body>
            <script>
                window.onload = () => {
                    window.webkit.messageHandlers.converterBridge.postMessage({ type: 'ready' });
                };

                async function convertObjToGLB(objURI, mtlURI, basePath) {


                    try {
                        let manager = new THREE.LoadingManager();
                        let originalFetch = window.fetch;
                        
                        manager.setURLModifier(url => {
                            if (url.startsWith('http') || url.startsWith('data:') || url.startsWith('blob:')) return url;
                            return basePath + '/' + url;
                        });

                        const mtlLoader = new THREE.MTLLoader(manager);
                        if (mtlURI && mtlURI !== "") {
                            mtlLoader.setPath('');
                        }
                        
                        let materials = await new Promise((resolve, reject) => {
                            if (!mtlURI || mtlURI === "") resolve(null);
                            mtlLoader.load(mtlURI, resolve, null, reject);
                        });
                        
                        if (materials) materials.preload();
                        
                        const objLoader = new THREE.OBJLoader(manager);
                        if (materials) objLoader.setMaterials(materials);
                        
                        let group = await new Promise((resolve, reject) => {
                            objLoader.load(objURI, resolve, null, reject);
                        });
                        
                        const exporter = new THREE.GLTFExporter();
                        exporter.parse(group, (result) => {
                            window.webkit.messageHandlers.converterBridge.postMessage({ 
                                type: 'success', 
                                data: result 
                            });
                        }, (error) => {
                            window.webkit.messageHandlers.converterBridge.postMessage({ 
                                type: 'error', 
                                message: error.message 
                            });
                        }, { binary: true });
                        
                    } catch (e) {
                        window.webkit.messageHandlers.converterBridge.postMessage({ 
                            type: 'error', 
                            message: e.toString() 
                        });
                    }
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(htmlSource, baseURL: URL(string: "http://localhost"))
    }
    
    // OBJ file e MTL file usando URLs nativas file://... passaremos path.
    func convert(objLocalPath: String, mtlLocalPath: String?, basePath: String, completion: @escaping (URL?, Error?) -> Void) {
        self.onComplete = completion
        
        let exec = {
            // Converter path em app://local/.. 
            // O basePath precisa ser app://local/PastaDoScan/ pra carregar texturas relativas
            let jsObj = "app://local\(objLocalPath)"
            let jsMtl = mtlLocalPath != nil ? "app://local\(mtlLocalPath!)" : ""
            let jsBase = "app://local\(basePath)"
            
            let call = "convertObjToGLB('\(jsObj)', '\(jsMtl)', '\(jsBase)');"
            self.webView.evaluateJavaScript(call)
        }
        
        if isEngineReady {
            exec()
        } else {
            pendingTask = exec
            startEngine()
        }
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "converterBridge",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        
        if type == "ready" {
            isEngineReady = true
            pendingTask?()
            pendingTask = nil
        } 
        else if type == "error" {
            let msg = body["message"] as? String ?? "Unknown error"
            onComplete?(nil, NSError(domain: "GLBConverterEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        else if type == "success" {
            guard let data = body["data"] as? Data else {
                onComplete?(nil, NSError(domain: "GLBConverterEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Falha ao obter dados binários do GLB."]))
                return
            }
            
            do {
                let dir = tempGLBURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                
                try data.write(to: tempGLBURL)
                onComplete?(tempGLBURL, nil)
            } catch {
                onComplete?(nil, error)
            }
        }
    }
}
