import RealityKit
import SwiftUI

@available(iOS 17.0, *)
@MainActor
func testFB() {
    let session = ObjectCaptureSession()
    print(session.numberOfShotsTaken)
}
