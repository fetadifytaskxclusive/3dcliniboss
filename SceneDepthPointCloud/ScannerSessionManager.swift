import SwiftUI
import RealityKit
import ARKit

@available(iOS 17.0, *)
@MainActor
final class ScannerSessionManager: ObservableObject {
    @Published var standardSession = ObjectCaptureSession()
    @Published var experimentalSession = ObjectCaptureSession()
    
    // Dados da Malha Volumétrica do LiDAR (Traseiro)
    @Published var capturedHeadMesh: ARMeshAnchor? = nil

    // Chame isso caso necessite restaurar a sessão para um novo scan
    // Diretórios Experimentais
    var experimentalImagesFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ExperimentalScans/Images", isDirectory: true)
    }

    var experimentalCheckpointFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ExperimentalScans/Checkpoints", isDirectory: true)
    }

    func resetStandard() {
        standardSession = ObjectCaptureSession()
    }
    
    func resetExperimental() {
        experimentalSession = ObjectCaptureSession()
    }
}
