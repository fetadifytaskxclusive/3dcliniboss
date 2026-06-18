import Foundation
import SceneKit
import Vision
import AppKit

let inputPath = "/Users/joaopaulogaldinodealencar/Downloads/scan 4.usdz"
let usdzURL = URL(fileURLWithPath: inputPath)
guard let scene = try? SCNScene(url: usdzURL, options: nil) else { exit(1) }

let wrapperNode = SCNNode()
for child in Array(scene.rootNode.childNodes) { wrapperNode.addChildNode(child) }
scene.rootNode.addChildNode(wrapperNode)
let (minVec, maxVec) = wrapperNode.boundingBox
print("Bounding Box - X: \(minVec.x) to \(maxVec.x), Y: \(minVec.y) to \(maxVec.y), Z: \(minVec.z) to \(maxVec.z)")
