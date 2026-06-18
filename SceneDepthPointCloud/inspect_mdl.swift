import Foundation
import ModelIO

let url = URL(fileURLWithPath: "/Users/joaopaulogaldinodealencar/Downloads/scan 4.usdz")
let asset = MDLAsset(url: url)
print("Asset has \(asset.count) objects")
for i in 0..<asset.count {
    let obj = asset.object(at: i)
    print("Object \(i): \(type(of: obj))")
}
