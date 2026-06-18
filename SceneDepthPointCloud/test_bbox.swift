import RealityKit

@available(iOS 17.0, *)
func test() {
    var session = ObjectCaptureSession()
    print(session.boundingBox ?? "nil")
}
