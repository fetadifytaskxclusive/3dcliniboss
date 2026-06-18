//
//  DepthBasedTriangulation.swift
//  SceneDepthPointCloud
//
//  Triangulação otimizada para dados de profundidade estruturados (ARKit)

import Foundation
import simd
import SceneKit

struct GridKey3D: Hashable {
    let x: Int
    let y: Int
    let z: Int
}

struct GridKey2D: Hashable {
    let x: Int
    let y: Int
}

struct TriangleKey: Hashable {
    let i: Int
    let j: Int
    let k: Int
    
    init(_ a: Int, _ b: Int, _ c: Int) {
        // Fast sort for 3 items
        var v1 = a, v2 = b, v3 = c
        if v1 > v2 { swap(&v1, &v2) }
        if v2 > v3 { swap(&v2, &v3) }
        if v1 > v2 { swap(&v1, &v2) }
        self.i = v1
        self.j = v2
        self.k = v3
    }
}

class DepthBasedTriangulation {
    
    // MARK: - Outlier Removal (Radius/Voxel Based)
    
    /// Algoritmo ultrarrápido O(N) para limpar ruídos flutuantes (fantasmas)
    static func removeOutliers(points: [Point3D], minNeighbors: Int = 10, radius: Float = 0.04) -> [Point3D] {
        print("🧹 Iniciando Filtro de Ruído (Radius Outlier Removal)...")
        guard points.count > minNeighbors else { return points }
        
        // Construir grade espacial 3D MUITO RÁPIDO (sem strings)
        var grid: [GridKey3D: Int] = [:]
        grid.reserveCapacity(points.count)
        
        // Contar pontos por célula
        for point in points {
            let key = GridKey3D(x: Int(floor(point.x / radius)),
                                y: Int(floor(point.y / radius)),
                                z: Int(floor(point.z / radius)))
            grid[key, default: 0] += 1
        }
        
        var filteredPoints: [Point3D] = []
        filteredPoints.reserveCapacity(points.count)
        
        let offsets = [
            GridKey3D(x:0, y:0, z:0), GridKey3D(x:1, y:0, z:0), GridKey3D(x:-1, y:0, z:0),
            GridKey3D(x:0, y:1, z:0), GridKey3D(x:0, y:-1, z:0), GridKey3D(x:0, y:0, z:1), GridKey3D(x:0, y:0, z:-1)
        ]
        
        for point in points {
            let baseX = Int(floor(point.x / radius))
            let baseY = Int(floor(point.y / radius))
            let baseZ = Int(floor(point.z / radius))
            
            var neighborCount = 0
            for offset in offsets {
                let key = GridKey3D(x: baseX + offset.x, y: baseY + offset.y, z: baseZ + offset.z)
                if let count = grid[key] {
                    neighborCount += count
                }
            }
            
            // Se tiver vizinhos suficientes, sobrevive
            if neighborCount >= minNeighbors {
                filteredPoints.append(point)
            }
        }
        
        print("🗑️ Pontos fantasma removidos: \(points.count - filteredPoints.count)")
        print("✨ Pontos válidos restantes: \(filteredPoints.count)")
        
        return filteredPoints
    }
    
    // MARK: - Structured Grid Triangulation
    
    /// Melhor para nuvens de pontos capturadas de depth cameras (ARKit, LiDAR)
    /// porque mantém a estrutura de grade implícita
    static func triangulateStructuredPointCloud(
        points: [Point3D],
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) -> [Int32] {
        
        print("🔄 Triangulação para dados estruturados...")
        print("📊 Pontos: \(points.count)")
        
        // Se temos dimensões da imagem, usamos triangulação estruturada
        if let width = imageWidth, let height = imageHeight {
            return triangulateGridBased(points: points, width: width, height: height)
        }
        
        // Caso contrário, tentamos reconstruir a grade
        return triangulateReconstructedGrid(points: points)
    }
    
    // MARK: - Grid-Based Triangulation
    
    private static func triangulateGridBased(points: [Point3D], width: Int, height: Int) -> [Int32] {
        var indices: [Int32] = []
        
        print("📐 Usando triangulação de grade: \(width)x\(height)")
        
        // Criar malha estruturada
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let i0 = y * width + x
                let i1 = y * width + (x + 1)
                let i2 = (y + 1) * width + x
                let i3 = (y + 1) * width + (x + 1)
                
                guard i0 < points.count && i1 < points.count && 
                      i2 < points.count && i3 < points.count else { continue }
                
                // Verificar se pontos são válidos (não muito distantes)
                let p0 = points[i0]
                let p1 = points[i1]
                let p2 = points[i2]
                let p3 = points[i3]
                
                let maxEdge: Float = 0.1 // Ajustar conforme necessário
                
                // Triângulo 1: (i0, i1, i2)
                if isValidTriangle(p0, p1, p2, maxEdge: maxEdge) {
                    indices.append(Int32(i0))
                    indices.append(Int32(i1))
                    indices.append(Int32(i2))
                }
                
                // Triângulo 2: (i1, i3, i2)
                if isValidTriangle(p1, p3, p2, maxEdge: maxEdge) {
                    indices.append(Int32(i1))
                    indices.append(Int32(i3))
                    indices.append(Int32(i2))
                }
            }
        }
        
        print("✅ Gerados: \(indices.count / 3) triângulos")
        return indices
    }
    
    // MARK: - Reconstructed Grid Triangulation
    
    private static func triangulateReconstructedGrid(points: [Point3D]) -> [Int32] {
        print("🔄 Reconstruindo grade implícita...")
        
        // Tentar detectar estrutura de grade analisando padrões de vizinhança
        let gridInfo = detectGridStructure(points: points)
        
        if let width = gridInfo.width, let height = gridInfo.height {
            print("✅ Grade detectada: \(width)x\(height)")
            return triangulateGridBased(points: points, width: width, height: height)
        }
        
        // Fallback: Triangulação de Delaunay 2.5D
        print("⚠️ Grade não detectada, usando Delaunay 2.5D...")
        return triangulateDelaunay25D(points: points)
    }
    
    // MARK: - Detect Grid Structure
    
    private static func detectGridStructure(points: [Point3D]) -> (width: Int?, height: Int?) {
        guard points.count > 100 else { return (nil, nil) }
        
        // Amostrar primeiros 100 pontos e tentar detectar padrão
        var distances: [Float] = []
        
        for i in 0..<min(100, points.count - 1) {
            let dist = distance(points[i], points[i + 1])
            if dist > 0.0001 && dist < 1.0 { // Filtrar outliers
                distances.append(dist)
            }
        }
        
        guard !distances.isEmpty else { return (nil, nil) }
        
        distances.sort()
        let medianDist = distances[distances.count / 2]
        
        // Estimar largura contando pontos consecutivos com distância similar
        var rowLength = 1
        for i in 0..<min(points.count - 1, 1000) {
            let dist = distance(points[i], points[i + 1])
            if abs(dist - medianDist) < medianDist * 0.5 {
                rowLength += 1
            } else {
                break
            }
        }
        
        if rowLength > 10 && points.count % rowLength == 0 {
            let height = points.count / rowLength
            return (rowLength, height)
        }
        
        return (nil, nil)
    }
    
    // MARK: - Delaunay 2.5D Triangulation
    
    private static func triangulateDelaunay25D(points: [Point3D]) -> [Int32] {
        var indices: [Int32] = []
        
        // Projetar pontos em plano dominante
        let plane = findDominantPlane(points: points)
        let projectedPoints = points.map { projectToPlane($0, plane: plane) }
        
        // Criar grade espacial
        let grid = buildSpatialGrid2D(projectedPoints: projectedPoints)
        
        var created = 0
        var processedEdges = Set<TriangleKey>()
        processedEdges.reserveCapacity(points.count * 2)
        
        // Para cada ponto, conectar com vizinhos próximos
        for i in 0..<points.count {
            let neighbors = findNearest2DNeighbors(
                index: i,
                projectedPoints: projectedPoints,
                grid: grid,
                k: 8
            )
            
            // Criar triângulos com vizinhos mais próximos
            for j in 0..<neighbors.count {
                for k in (j+1)..<neighbors.count {
                    let idx2 = neighbors[j]
                    let idx3 = neighbors[k]
                    
                    let key = TriangleKey(i, idx2, idx3)
                    guard !processedEdges.contains(key) else { continue }
                    processedEdges.insert(key)
                    
                    // Validar triângulo (usando uma verificação muito rápida antes da área)
                    if isValidTriangle(points[i], points[idx2], points[idx3], maxEdge: 0.10) {
                        indices.append(Int32(i))
                        indices.append(Int32(idx2))
                        indices.append(Int32(idx3))
                        created += 1
                    }
                }
            }
        }
        
        print("✅ Delaunay 2.5D gerou: \(created) triângulos")
        return indices
    }
    
    // MARK: - Validation
    
    private static func isValidTriangle(_ p0: Point3D, _ p1: Point3D, _ p2: Point3D, maxEdge: Float) -> Bool {
        let d01 = distance(p0, p1)
        let d12 = distance(p1, p2)
        let d20 = distance(p2, p0)
        
        // Rejeitar se arestas muito longas
        guard d01 < maxEdge && d12 < maxEdge && d20 < maxEdge else {
            return false
        }
        
        // Rejeitar triângulos degenerados
        let area = triangleArea(p0, p1, p2)
        guard area > 0.00001 else {
            return false
        }
        
        // Rejeitar triângulos muito finos
        let longestEdge = max(d01, max(d12, d20))
        let shortestEdge = min(d01, min(d12, d20))
        let aspectRatio = shortestEdge / longestEdge
        
        return aspectRatio > 0.2
    }
    
    // MARK: - Geometry Helpers
    
    private static func distance(_ p1: Point3D, _ p2: Point3D) -> Float {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        let dz = p1.z - p2.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    private static func triangleArea(_ p0: Point3D, _ p1: Point3D, _ p2: Point3D) -> Float {
        let a = simd_float3(p0.x, p0.y, p0.z)
        let b = simd_float3(p1.x, p1.y, p1.z)
        let c = simd_float3(p2.x, p2.y, p2.z)
        
        let cross = simd_cross(b - a, c - a)
        return simd_length(cross) / 2.0
    }
    
    // MARK: - Plane Fitting
    
    private static func findDominantPlane(points: [Point3D]) -> (normal: simd_float3, point: simd_float3) {
        // PCA simplificado para encontrar plano dominante
        var centroid = simd_float3(0, 0, 0)
        
        for point in points.prefix(min(1000, points.count)) {
            centroid += simd_float3(point.x, point.y, point.z)
        }
        centroid /= Float(min(1000, points.count))
        
        // Retornar plano XY por padrão (comum em depth cameras)
        return (simd_float3(0, 0, 1), centroid)
    }
    
    private static func projectToPlane(_ point: Point3D, plane: (normal: simd_float3, point: simd_float3)) -> simd_float2 {
        // Projetar em plano XY para simplificar
        return simd_float2(point.x, point.y)
    }
    
    // MARK: - 2D Spatial Grid
    
    private static func buildSpatialGrid2D(projectedPoints: [simd_float2]) -> [GridKey2D: [Int]] {
        var grid: [GridKey2D: [Int]] = [:]
        grid.reserveCapacity(projectedPoints.count)
        
        // Max edge é o tamanho da célula (para vizinhos locais rápidos)
        let cellSize: Float = 0.05
        
        for (index, point) in projectedPoints.enumerated() {
            let key = GridKey2D(x: Int(point.x / cellSize), y: Int(point.y / cellSize))
            grid[key, default: []].append(index)
        }
        
        return grid
    }
    
    private static func findNearest2DNeighbors(
        index: Int,
        projectedPoints: [simd_float2],
        grid: [GridKey2D: [Int]],
        k: Int
    ) -> [Int] {
        let point = projectedPoints[index]
        let cellSize: Float = 0.05
        
        let centerX = Int(point.x / cellSize)
        let centerY = Int(point.y / cellSize)
        
        var candidates: [Int] = []
        // Busca 1 celula vizinha de distancia para ultra velocidade (-1..1 em vez de -2..2)
        for dx in -1...1 {
            for dy in -1...1 {
                let key = GridKey2D(x: centerX + dx, y: centerY + dy)
                if let indices = grid[key] {
                    candidates.append(contentsOf: indices)
                }
            }
        }
        
        let distances = candidates.compactMap { candidateIdx -> (Int, Float)? in
            guard candidateIdx != index else { return nil }
            let dist = simd_distance(point, projectedPoints[candidateIdx])
            return (candidateIdx, dist)
        }
        
        let sorted = distances.sorted { $0.1 < $1.1 }
        return Array(sorted.prefix(k).map { $0.0 })
    }
}
