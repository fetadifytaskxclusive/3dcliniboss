import Foundation
import SceneKit
import GLTFSceneKit

let scene = SCNScene()
let exporter = try! GLTFExporter(scene: scene)
let data = try! exporter.export(to: .glb)
print("GLTFExporter exists")
