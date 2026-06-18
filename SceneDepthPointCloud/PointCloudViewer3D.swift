//
//  PointCloudViewer3D_CLEAN.swift
//  SceneDepthPointCloud
//  
//  ARQUIVO LIMPO E FUNCIONAL
//  RENOMEIE PARA: PointCloudViewer3D.swift

import UIKit
import SceneKit

class PointCloudViewer3D: UIViewController {
    var fileURL: URL!
    
    private var sceneView: SCNView!
    private var scene: SCNScene!
    private var cameraNode: SCNNode!
    private var pointCloudNode: SCNNode!
    private var meshNode: SCNNode?
    private var loadingLabel: UILabel!
    private var closeButton: UIButton!
    private var infoLabel: UILabel!
    private var convertToMeshButton: UIButton!
    private var applyTextureButton: UIButton!
    private var qualityControl: UISegmentedControl!
    private var methodControl: UISegmentedControl!
    
    private var points: [Point3D] = []
    private var isMeshMode = false
    private var hasTexture = false
    
    // MARK: - Enums
    
    enum TriangulationMethod {
        case gridBased
        case delaunay
        case simple
        
        var displayName: String {
            switch self {
            case .gridBased: return "Grade"
            case .delaunay: return "Delaunay"
            case .simple: return "Simples"
            }
        }
        
        var description: String {
            switch self {
            case .gridBased: return "🔲 Grid-Based\nPara depth data estruturado"
            case .delaunay: return "📐 Delaunay 2.5D\nAlgoritmo nativo"
            case .simple: return "⚡ Simples\nFallback garantido"
            }
        }
    }
    
    private var selectedMethod: TriangulationMethod = .gridBased
    
    enum MeshQuality {
        case low, medium, high
        
        var neighborCount: Int {
            switch self {
            case .low: return 5
            case .medium: return 8
            case .high: return 12
            }
        }
    }
    
    private var meshQuality: MeshQuality = .medium
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupUI()
        loadPointCloud()
    }
    
    // MARK: - Setup
    
    private func setupScene() {
        sceneView = SCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = .black
        sceneView.showsStatistics = true
        view.addSubview(sceneView)
        
        scene = SCNScene()
        sceneView.scene = scene
        
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 3)
        scene.rootNode.addChildNode(cameraNode)
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white
        ambientLight.light?.intensity = 1000
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.color = UIColor.white
        directionalLight.light?.intensity = 1000
        directionalLight.position = SCNVector3(x: 0, y: 5, z: 5)
        scene.rootNode.addChildNode(directionalLight)
    }
    
    private func setupUI() {
        loadingLabel = UILabel()
        loadingLabel.text = "Carregando nuvem de pontos..."
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 16, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingLabel.layer.cornerRadius = 8
        loadingLabel.layer.masksToBounds = true
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        
        closeButton = UIButton(type: .system)
        closeButton.setTitle("Fechar", for: .normal)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 8
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeViewer), for: .touchUpInside)
        view.addSubview(closeButton)
        
        infoLabel = UILabel()
        infoLabel.text = "Use 2 dedos para rotacionar\nPinch para zoom"
        infoLabel.textColor = .white
        infoLabel.font = .systemFont(ofSize: 14)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        infoLabel.layer.cornerRadius = 8
        infoLabel.layer.masksToBounds = true
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)
        
        convertToMeshButton = UIButton(type: .system)
        convertToMeshButton.setTitle("Converter em Malha", for: .normal)
        convertToMeshButton.setImage(UIImage(systemName: "cube.fill"), for: .normal)
        convertToMeshButton.tintColor = .systemBlue
        convertToMeshButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        convertToMeshButton.layer.cornerRadius = 8
        convertToMeshButton.translatesAutoresizingMaskIntoConstraints = false
        convertToMeshButton.addTarget(self, action: #selector(convertToMesh), for: .touchUpInside)
        convertToMeshButton.isHidden = true
        view.addSubview(convertToMeshButton)
        
        applyTextureButton = UIButton(type: .system)
        applyTextureButton.setTitle("Aplicar Textura", for: .normal)
        applyTextureButton.setImage(UIImage(systemName: "paintbrush.fill"), for: .normal)
        applyTextureButton.tintColor = .systemGreen
        applyTextureButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        applyTextureButton.layer.cornerRadius = 8
        applyTextureButton.translatesAutoresizingMaskIntoConstraints = false
        applyTextureButton.addTarget(self, action: #selector(applyTexture), for: .touchUpInside)
        applyTextureButton.isHidden = true
        view.addSubview(applyTextureButton)
        
        qualityControl = UISegmentedControl(items: ["Baixa", "Média", "Alta"])
        qualityControl.selectedSegmentIndex = 1
        qualityControl.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        qualityControl.selectedSegmentTintColor = .systemBlue
        qualityControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        qualityControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        qualityControl.translatesAutoresizingMaskIntoConstraints = false
        qualityControl.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        qualityControl.isHidden = true
        view.addSubview(qualityControl)
        
        methodControl = UISegmentedControl(items: ["Grade", "Delaunay", "Simples"])
        methodControl.selectedSegmentIndex = 0
        methodControl.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        methodControl.selectedSegmentTintColor = .systemGreen
        methodControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        methodControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.boldSystemFont(ofSize: 12)], for: .selected)
        methodControl.translatesAutoresizingMaskIntoConstraints = false
        methodControl.addTarget(self, action: #selector(methodChanged), for: .valueChanged)
        methodControl.isHidden = true
        view.addSubview(methodControl)
        
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingLabel.widthAnchor.constraint(equalToConstant: 280),
            loadingLabel.heightAnchor.constraint(equalToConstant: 50),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 100),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            infoLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            infoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoLabel.widthAnchor.constraint(equalToConstant: 250),
            infoLabel.heightAnchor.constraint(equalToConstant: 60),
            
            convertToMeshButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            convertToMeshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            convertToMeshButton.widthAnchor.constraint(equalToConstant: 160),
            convertToMeshButton.heightAnchor.constraint(equalToConstant: 44),
            
            applyTextureButton.topAnchor.constraint(equalTo: convertToMeshButton.bottomAnchor, constant: 12),
            applyTextureButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            applyTextureButton.widthAnchor.constraint(equalToConstant: 160),
            applyTextureButton.heightAnchor.constraint(equalToConstant: 44),
            
            qualityControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            qualityControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qualityControl.widthAnchor.constraint(equalToConstant: 240),
            qualityControl.heightAnchor.constraint(equalToConstant: 32),
            
            methodControl.topAnchor.constraint(equalTo: qualityControl.bottomAnchor, constant: 8),
            methodControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            methodControl.widthAnchor.constraint(equalToConstant: 240),
            methodControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    // MARK: - Loading
    
    private func loadPointCloud() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let points = try self.parsePLYFile(url: self.fileURL)
                self.points = points
                
                DispatchQueue.main.async {
                    self.loadingLabel.text = "Renderizando \(points.count) pontos..."
                }
                
                let geometry = self.createPointCloudGeometry(from: points)
                
                DispatchQueue.main.async {
                    self.pointCloudNode = SCNNode(geometry: geometry)
                    self.scene.rootNode.addChildNode(self.pointCloudNode)
                    
                    let (min, max) = geometry.boundingBox
                    let center = SCNVector3(
                        (min.x + max.x) / 2,
                        (min.y + max.y) / 2,
                        (min.z + max.z) / 2
                    )
                    self.pointCloudNode.position = SCNVector3(-center.x, -center.y, -center.z)
                    
                    self.loadingLabel.isHidden = true
                    self.infoLabel.text = "\(points.count) pontos\nUse 2 dedos para rotacionar"
                    self.convertToMeshButton.isHidden = false
                    self.qualityControl.isHidden = false
                    self.methodControl.isHidden = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadingLabel.text = "Erro ao carregar arquivo"
                    self.loadingLabel.textColor = .red
                }
            }
        }
    }
    
    private func parsePLYFile(url: URL) throws -> [Point3D] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var vertexCount = 0
        var headerEnded = false
        var points: [Point3D] = []
        
        for line in lines {
            if line.starts(with: "element vertex") {
                let components = line.components(separatedBy: " ")
                if components.count >= 3 {
                    vertexCount = Int(components[2]) ?? 0
                }
            }
            if line.starts(with: "end_header") {
                headerEnded = true
                continue
            }
            
            if headerEnded && !line.isEmpty {
                let components = line.components(separatedBy: " ")
                if components.count >= 6 {
                    if let x = Float(components[0]),
                       let y = Float(components[1]),
                       let z = Float(components[2]),
                       let r = Float(components[3]),
                       let g = Float(components[4]),
                       let b = Float(components[5]) {
                        
                        let point = Point3D(
                            x: x, y: y, z: z,
                            r: r / 255.0, g: g / 255.0, b: b / 255.0
                        )
                        points.append(point)
                    }
                }
                
                if points.count >= vertexCount { break }
            }
        }
        
        return points
    }
    
    private func createPointCloudGeometry(from points: [Point3D]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        
        for point in points {
            vertices.append(SCNVector3(point.x, point.y, point.z))
            colors.append(UIColor(red: CGFloat(point.r), 
                                green: CGFloat(point.g), 
                                blue: CGFloat(point.b), 
                                alpha: 1.0))
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        var colorComponents: [Float] = []
        for color in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colorComponents.append(Float(r))
            colorComponents.append(Float(g))
            colorComponents.append(Float(b))
        }
        
        let colorData = Data(bytes: colorComponents, count: colorComponents.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
        
        var indices: [Int32] = []
        for i in 0..<vertices.count {
            indices.append(Int32(i))
        }
        
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
    
    // MARK: - Actions
    
    @objc private func closeViewer() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func qualityChanged() {
        switch qualityControl.selectedSegmentIndex {
        case 0:
            meshQuality = .low
            infoLabel.text = "Qualidade: Baixa (rápido)"
        case 1:
            meshQuality = .medium
            infoLabel.text = "Qualidade: Média (balanceado)"
        case 2:
            meshQuality = .high
            infoLabel.text = "Qualidade: Alta (detalhado)"
        default:
            meshQuality = .medium
        }
    }
    
    @objc private func methodChanged() {
        switch methodControl.selectedSegmentIndex {
        case 0:
            selectedMethod = .gridBased
        case 1:
            selectedMethod = .delaunay
        case 2:
            selectedMethod = .simple
        default:
            selectedMethod = .gridBased
        }
        
        infoLabel.text = selectedMethod.description
    }
    
    @objc private func convertToMesh() {
        guard !points.isEmpty else { return }
        
        loadingLabel.isHidden = false
        loadingLabel.text = "Limpando ruídos e gerando malha..."
        loadingLabel.textColor = .white
        convertToMeshButton.isEnabled = false
        qualityControl.isEnabled = false
        methodControl.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.loadingLabel.text = "Removendo outliers (SOR)..."
            }
            // 1. LIMPAR RUÍDOS FANTASMAS (Statistical/Radius Outlier Removal)
            // minNeighbors: 8, radius: 5cm - ajustado perfeitamente para humanos e rostos
            let cleanPoints = DepthBasedTriangulation.removeOutliers(points: self.points, minNeighbors: 8, radius: 0.05)
            self.points = cleanPoints // Atualiza o array mestre para q a textura tbm use pontos limpos
            
            DispatchQueue.main.async {
                self.loadingLabel.text = "Gerando malha (\(self.selectedMethod.displayName))..."
            }
            
            // 2. GERAR MALHA DA NUVEM LIMPA
            let meshGeometry = self.generateMesh(from: cleanPoints)
            
            DispatchQueue.main.async {
                self.pointCloudNode?.removeFromParentNode()
                
                self.meshNode = SCNNode(geometry: meshGeometry)
                if let position = self.pointCloudNode?.position {
                    self.meshNode?.position = position
                }
                self.scene.rootNode.addChildNode(self.meshNode!)
                
                self.loadingLabel.isHidden = true
                self.infoLabel.text = "Malha gerada!"
                self.isMeshMode = true
                
                self.convertToMeshButton.isHidden = true
                self.qualityControl.isHidden = true
                self.methodControl.isHidden = true
                self.applyTextureButton.isHidden = false
            }
        }
    }
    
    @objc private func applyTexture() {
        guard let meshNode = meshNode, !hasTexture else { return }
        
        loadingLabel.isHidden = false
        loadingLabel.text = "Aplicando textura..."
        applyTextureButton.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let texturedGeometry = self.applyVertexColors(to: meshNode.geometry!)
            
            DispatchQueue.main.async {
                meshNode.geometry = texturedGeometry
                
                self.loadingLabel.isHidden = true
                self.infoLabel.text = "Textura aplicada!"
                self.hasTexture = true
                
                self.applyTextureButton.setTitle("Remover Textura", for: .normal)
                self.applyTextureButton.tintColor = .systemOrange
                self.applyTextureButton.isEnabled = true
                self.applyTextureButton.removeTarget(nil, action: nil, for: .allEvents)
                self.applyTextureButton.addTarget(self, action: #selector(self.removeTexture), for: .touchUpInside)
            }
        }
    }
    
    @objc private func removeTexture() {
        guard let meshNode = meshNode, hasTexture else { return }
        
        if let geometry = meshNode.geometry {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.lightGray
            material.lightingModel = .phong
            geometry.materials = [material]
        }
        
        hasTexture = false
        infoLabel.text = "Textura removida"
        
        applyTextureButton.setTitle("Aplicar Textura", for: .normal)
        applyTextureButton.tintColor = .systemGreen
        applyTextureButton.removeTarget(nil, action: nil, for: .allEvents)
        applyTextureButton.addTarget(self, action: #selector(applyTexture), for: .touchUpInside)
    }
    
    // MARK: - Mesh Generation
    
    private func generateMesh(from points: [Point3D]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        for point in points {
            vertices.append(SCNVector3(point.x, point.y, point.z))
        }
        
        var indices: [Int32] = []
        
        print("🎯 Método: \(selectedMethod.displayName)")
        
        switch selectedMethod {
        case .gridBased:
            print("📐 Grid-Based...")
            indices = DepthBasedTriangulation.triangulateStructuredPointCloud(points: points)
            
        case .delaunay:
            print("📐 Delaunay...")
            indices = simpleDelaunay(points: points, maxDistance: 0.1)
            
        case .simple:
            print("⚡ Simples...")
            indices = createSimpleMeshFallback(points: points)
        }
        
        if indices.isEmpty {
            print("⚠️ Fallback...")
            indices = createSimpleMeshFallback(points: points)
        }
        
        if indices.isEmpty {
            print("🆘 Mínimo...")
            indices = createMinimalVisualization(pointCount: points.count)
        }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.lightGray
        material.lightingModel = .phong
        material.isDoubleSided = true
        geometry.materials = [material]
        
        print("✅ \(indices.count / 3) triângulos")
        
        return geometry
    }
    
    // MARK: - Triangulation Methods
    
    private func simpleDelaunay(points: [Point3D], maxDistance: Float) -> [Int32] {
        var indices: [Int32] = []
        var created = 0
        
        for i in 0..<points.count {
            for j in (i+1)..<min(i+10, points.count) {
                for k in (j+1)..<min(i+12, points.count) {
                    let p1 = points[i]
                    let p2 = points[j]
                    let p3 = points[k]
                    
                    let d12 = distance(p1, p2)
                    let d23 = distance(p2, p3)
                    let d31 = distance(p3, p1)
                    
                    if d12 < maxDistance && d23 < maxDistance && d31 < maxDistance {
                        let area = triangleAreaSimple(p1, p2, p3)
                        if area > 0.00001 {
                            indices.append(Int32(i))
                            indices.append(Int32(j))
                            indices.append(Int32(k))
                            created += 1
                        }
                    }
                }
            }
            if created > 15000 { break }
        }
        
        print("✅ Delaunay: \(created) triângulos")
        return indices
    }
    
    private func createSimpleMeshFallback(points: [Point3D]) -> [Int32] {
        print("🔧 Fallback simples...")
        
        var indices: [Int32] = []
        let maxDistance: Float = 0.05
        var created = 0
        
        for i in 0..<min(points.count, 3000) {
            for j in (i+1)..<min(i+4, points.count) {
                for k in (j+1)..<min(i+5, points.count) {
                    let p1 = points[i]
                    let p2 = points[j]
                    let p3 = points[k]
                    
                    let d12 = distance(p1, p2)
                    let d23 = distance(p2, p3)
                    let d31 = distance(p3, p1)
                    
                    if d12 < maxDistance && d23 < maxDistance && d31 < maxDistance {
                        let area = triangleAreaSimple(p1, p2, p3)
                        if area > 0.00001 {
                            indices.append(Int32(i))
                            indices.append(Int32(j))
                            indices.append(Int32(k))
                            created += 1
                        }
                    }
                }
            }
            if created > 5000 { break }
        }
        
        print("✅ Simples: \(created) triângulos")
        return indices
    }
    
    private func createMinimalVisualization(pointCount: Int) -> [Int32] {
        print("🆘 Visualização mínima...")
        var indices: [Int32] = []
        let step = max(1, pointCount / 100)
        
        for i in stride(from: 0, to: min(pointCount - 2, 300), by: step) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
            indices.append(Int32(i + 2))
        }
        
        print("✅ Mínimo: \(indices.count / 3) triângulos")
        return indices
    }
    
    // MARK: - Helper Functions
    
    private func distance(_ p1: Point3D, _ p2: Point3D) -> Float {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        let dz = p1.z - p2.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    private func triangleAreaSimple(_ p1: Point3D, _ p2: Point3D, _ p3: Point3D) -> Float {
        let a = simd_float3(p1.x, p1.y, p1.z)
        let b = simd_float3(p2.x, p2.y, p2.z)
        let c = simd_float3(p3.x, p3.y, p3.z)
        let cross = simd_cross(b - a, c - a)
        return simd_length(cross) / 2.0
    }
    
    private func applyVertexColors(to geometry: SCNGeometry) -> SCNGeometry {
        guard let vertexSource = geometry.sources(for: .vertex).first else {
            return geometry
        }
        
        let vertexCount = vertexSource.vectorCount
        var colorComponents: [Float] = []
        
        for i in 0..<min(vertexCount, points.count) {
            let point = points[i]
            colorComponents.append(point.r)
            colorComponents.append(point.g)
            colorComponents.append(point.b)
        }
        
        while colorComponents.count < vertexCount * 3 {
            colorComponents.append(0.5)
            colorComponents.append(0.5)
            colorComponents.append(0.5)
        }
        
        let colorData = Data(bytes: colorComponents, count: colorComponents.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
        
        let newGeometry = SCNGeometry(
            sources: [vertexSource, colorSource],
            elements: geometry.elements
        )
        
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.isDoubleSided = true
        newGeometry.materials = [material]
        
        return newGeometry
    }
}

// MARK: - Point3D

struct Point3D {
    let x: Float
    let y: Float
    let z: Float
    let r: Float
    let g: Float
    let b: Float
}
