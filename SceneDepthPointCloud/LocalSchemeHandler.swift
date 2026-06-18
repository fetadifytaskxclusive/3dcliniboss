import WebKit
import MobileCoreServices

@available(iOS 17.0, *)
class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalSchemeHandler", code: -1, userInfo: nil))
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pathStr = url.path // e.g. "/Scans/Models/uuid/model.obj"
        let fullPathURL = documentsPath.appendingPathComponent(pathStr)
        
        guard FileManager.default.fileExists(atPath: fullPathURL.path),
              let data = try? Data(contentsOf: fullPathURL) else {
            errorResponse(urlSchemeTask)
            return
        }
        
        let mimeType = mimeTypeForExtension(pathExtension: fullPathURL.pathExtension)
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Handle cancel
    }
    
    private func errorResponse(_ task: WKURLSchemeTask) {
        let response = HTTPURLResponse(url: task.request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        task.didReceive(response)
        task.didReceive(Data())
        task.didFinish()
    }
    
    private func mimeTypeForExtension(pathExtension: String) -> String {
        let ext = pathExtension.lowercased()
        switch ext {
        case "obj": return "text/plain"
        case "mtl": return "text/plain"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "html": return "text/html"
        case "js": return "application/javascript"
        default:
            return "application/octet-stream"
        }
    }
}
