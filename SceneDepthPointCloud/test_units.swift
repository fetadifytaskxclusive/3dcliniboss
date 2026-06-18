import Foundation
import ModelIO

let url = URL(fileURLWithPath: "scan_4_cropped.obj")
let asset = MDLAsset(url: url)
asset.metersPerUnit = 1.0 
print("MDLAsset metersPerUnit set to \(asset.metersPerUnit)")
