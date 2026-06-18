import ARKit
import SceneKit
import UIKit

func test() {
    let dev = MTLCreateSystemDefaultDevice()!
    let face = ARSCNFaceGeometry(device: dev)!
    print(face.sources.count)
    let colorData = Data()
    let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: 0, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
    let newGeo = SCNGeometry(sources: face.sources + [colorSource], elements: face.elements)
    print(newGeo)
}
test()
