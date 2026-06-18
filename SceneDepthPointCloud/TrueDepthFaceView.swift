import SwiftUI
import ARKit
import SceneKit

// MARK: - SwiftUI View

@available(iOS 17.0, *)
struct TrueDepthFaceView: View {
    @State private var showingPreview = false
    @State private var modelURL: URL?   = nil
    @State private var isExporting      = false

    var body: some View {
        ZStack {
            ARFaceCaptureViewContainer(modelURL: $modelURL, isExporting: $isExporting)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()

                if isExporting {
                    ProgressView("Texturizando Rosto...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 50)
                } else {
                    VStack(spacing: 8) {
                        Text("Posicione o rosto centralizado")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 2)

                        Button { isExporting = true } label: {
                            Label("Capturar Rosto 3D com Textura", systemImage: "face.smiling")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationTitle("TrueDepth Face")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPreview) {
            if let url = modelURL {
                ModelPreviewSheet(url: url, isPresented: $showingPreview)
            }
        }
        .onChange(of: modelURL) { _, new in
            if new != nil { isExporting = false; showingPreview = true }
        }
    }
}

// MARK: - UIViewRepresentable

@available(iOS 17.0, *)
struct ARFaceCaptureViewContainer: UIViewRepresentable {
    @Binding var modelURL:    URL?
    @Binding var isExporting: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.delegate = context.coordinator
        v.automaticallyUpdatesLighting = true
        context.coordinator.sceneView = v
        context.coordinator.startFaceTracking(on: v)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        guard isExporting, !context.coordinator.didStartExport else { return }
        context.coordinator.didStartExport = true
        // snapshot MUST happen on main thread, then export on bg
        let snap     = uiView.snapshot()
        let viewSize = uiView.bounds.size
        DispatchQueue.global(qos: .userInitiated).async {
            context.coordinator.export(from: uiView, snapshot: snap, viewSize: viewSize)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARFaceCaptureViewContainer
        weak var sceneView: ARSCNView?
        var didStartExport = false
        let device = MTLCreateSystemDefaultDevice()

        init(_ parent: ARFaceCaptureViewContainer) { self.parent = parent }

        // ── Face tracking ────────────────────────────────────────────────────────
        func startFaceTracking(on view: ARSCNView) {
            guard ARFaceTrackingConfiguration.isSupported else { return }
            let cfg = ARFaceTrackingConfiguration()
            cfg.isLightEstimationEnabled = true
            view.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }

        // Live overlay — semi-transparent, eyes filled for visual guidance
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor, let dev = device else { return nil }
            guard let geo = ARSCNFaceGeometry(device: dev, fillMesh: true) else { return nil }
            geo.firstMaterial?.diffuse.contents   = UIColor.white.withAlphaComponent(0.15)
            geo.firstMaterial?.isDoubleSided      = true
            return SCNNode(geometry: geo)
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let fa  = anchor as? ARFaceAnchor,
                  let geo = node.geometry as? ARSCNFaceGeometry else { return }
            geo.update(from: fa.geometry)
        }

        // ── Export ───────────────────────────────────────────────────────────────
        func export(from view: ARSCNView, snapshot: UIImage, viewSize: CGSize) {
            guard let dev     = device,
                  let frame   = view.session.currentFrame,
                  let anchor  = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
                  let fillGeo = ARSCNFaceGeometry(device: dev, fillMesh: true) else {
                failExport(); return
            }

            fillGeo.update(from: anchor.geometry)

            // ── Extract ALL vertex positions from the SCNGeometrySource ──────────
            // fillGeo has more verts than ARFaceGeometry (eye/mouth patches added)
            guard let posSrc = fillGeo.sources.first(where: { $0.semantic == .vertex }) else {
                failExport(); return
            }
            let positions = extractFloat3(from: posSrc)   // [simd_float3]

            // ── Project each vertex → screen coord → UV ──────────────────────────
            // ARCamera.projectPoint returns portrait pixel coords (origin = top-left).
            // UIImage also has origin top-left  ⟹  no V-flip needed.
            // U = x / width,  V = y / height
            let camera = frame.camera
            var uvData = [Float](); uvData.reserveCapacity(positions.count * 2)

            for v in positions {
                let world4 = anchor.transform * SIMD4<Float>(v.x, v.y, v.z, 1)
                let world3 = SIMD3<Float>(world4.x, world4.y, world4.z)
                let screen = camera.projectPoint(world3,
                                                 orientation: .portrait,
                                                 viewportSize: viewSize)
                let u = clamp01(Float(screen.x / viewSize.width))
                let v = clamp01(Float(screen.y / viewSize.height))
                uvData.append(u); uvData.append(v)
            }

            // ── Build new SCNGeometry replacing only the texcoord source ─────────
            let newUVBytes = uvData.withUnsafeBytes { Data($0) }
            let newUVSrc   = SCNGeometrySource(
                data: newUVBytes,          semantic: .texcoord,
                vectorCount: positions.count, usesFloatComponents: true,
                componentsPerVector: 2,    bytesPerComponent: 4,
                dataOffset: 0,            dataStride: 8)

            // Keep original position source, swap out texcoord
            let otherSources = fillGeo.sources.filter { $0.semantic != .texcoord }
            let finalGeo     = SCNGeometry(sources: otherSources + [newUVSrc],
                                           elements: fillGeo.elements)

            let mat = SCNMaterial()
            mat.diffuse.contents = snapshot
            mat.isDoubleSided    = true
            finalGeo.materials   = [mat]

            let scene = SCNScene()
            scene.rootNode.addChildNode(SCNNode(geometry: finalGeo))

            // ── Save USDZ ────────────────────────────────────────────────────────
            let docs   = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir    = docs.appendingPathComponent("ExperimentalScans/Face")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let outURL = dir.appendingPathComponent("face-\(UUID().uuidString).usdz")
            let ok     = scene.write(to: outURL, options: nil, delegate: nil, progressHandler: nil)

            DispatchQueue.main.async {
                if ok { self.parent.modelURL = outURL }
                self.parent.isExporting = false
                self.didStartExport     = false
            }
        }

        // ── SIMD3 extractor from SCNGeometrySource ───────────────────────────────
        private func extractFloat3(from source: SCNGeometrySource) -> [SIMD3<Float>] {
            let stride = source.dataStride
            let offset = source.dataOffset
            let count  = source.vectorCount
            return source.data.withUnsafeBytes { raw in
                (0..<count).map { i in
                    let base = raw.baseAddress!
                        .advanced(by: i * stride + offset)
                        .assumingMemoryBound(to: Float.self)
                    return SIMD3<Float>(base[0], base[1], base[2])
                }
            }
        }

        private func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }

        private func failExport() {
            DispatchQueue.main.async {
                self.parent.isExporting = false
                self.didStartExport     = false
            }
        }
    }
}
