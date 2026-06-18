import RealityKit

@available(iOS 17.0, *)
func test() {
    print(PhotogrammetrySession.Request.Detail.preview)
    print(PhotogrammetrySession.Request.Detail.reduced)
    print(PhotogrammetrySession.Request.Detail.medium)
    print(PhotogrammetrySession.Request.Detail.full)
    print(PhotogrammetrySession.Request.Detail.raw)
}
import RealityKit; let x: PhotogrammetrySession.Request.Detail = .preview
