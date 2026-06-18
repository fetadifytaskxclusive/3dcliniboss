require 'fileutils'

file = "/Users/joaopaulogaldinodealencar/Downloads/test_cropper.swift"
content = File.read(file)

# We will completely replace the OBJ manipulation part (Step 5) with our new Planar Clipper.

new_engine = <<-SWIFT
// 5. Motor de Corte Geométrico (Planar Clipper)
print("✂️ Lendo OBJ original (\\(objURL.lastPathComponent)) para aplicar o corte reto (Planar Clipping)...")

struct VertexData: Hashable {
    var p: SIMD3<Float>
    var uv: SIMD2<Float>
    var n: SIMD3<Float>
}

struct Plane {
    var normal: SIMD3<Float>
    var d: Float
    func distance(to p: SIMD3<Float>) -> Float { return simd_dot(p, normal) - d }
}

func clipPolygon(_ poly: [VertexData], against plane: Plane) -> [VertexData] {
    var output = [VertexData]()
    guard !poly.isEmpty else { return output }
    var prev = poly.last!
    var prevDist = plane.distance(to: prev.p)
    for curr in poly {
        let currDist = plane.distance(to: curr.p)
        if currDist >= 0 {
            if prevDist < 0 {
                let t = prevDist / (prevDist - currDist)
                output.append(VertexData(p: prev.p + (curr.p - prev.p) * t, uv: prev.uv + (curr.uv - prev.uv) * t, n: simd_normalize(prev.n + (curr.n - prev.n) * t)))
            }
            output.append(curr)
        } else if prevDist >= 0 {
            let t = prevDist / (prevDist - currDist)
            output.append(VertexData(p: prev.p + (curr.p - prev.p) * t, uv: prev.uv + (curr.uv - prev.uv) * t, n: simd_normalize(prev.n + (curr.n - prev.n) * t)))
        }
        prev = curr
        prevDist = currDist
    }
    return output
}

do {
    let content = try String(contentsOf: objURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
    
    var rawV = [SIMD3<Float>]()
    var rawVT = [SIMD2<Float>]()
    var rawVN = [SIMD3<Float>]()
    var materialHeader = [String]()
    var faces = [[(v: Int, vt: Int, vn: Int)]]()
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("mtllib ") || trimmed.hasPrefix("usemtl ") {
            materialHeader.append(trimmed)
        } else if trimmed.hasPrefix("v ") {
            let p = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            rawV.append(SIMD3<Float>(Float(p[1])!, Float(p[2])!, Float(p[3])!))
        } else if trimmed.hasPrefix("vt ") {
            let p = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            rawVT.append(SIMD2<Float>(Float(p[1])!, Float(p[2])!))
        } else if trimmed.hasPrefix("vn ") {
            let p = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            rawVN.append(SIMD3<Float>(Float(p[1])!, Float(p[2])!, Float(p[3])!))
        } else if trimmed.hasPrefix("f ") {
            let p = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.dropFirst()
            var faceData = [(v: Int, vt: Int, vn: Int)]()
            for part in p {
                let sub = part.components(separatedBy: "/")
                let vIdx = Int(sub[0])! - 1
                let vtIdx = sub.count > 1 && !sub[1].isEmpty ? Int(sub[1])! - 1 : 0
                let vnIdx = sub.count > 2 && !sub[2].isEmpty ? Int(sub[2])! - 1 : 0
                faceData.append((v: vIdx, vt: vtIdx, vn: vnIdx))
            }
            faces.append(faceData)
        }
    }
    
    // Configurar o Plano de Corte
    // Queremos um corte limpo e levemente inclinado.
    // normal = (0, 1, -slope), depois normalizado.
    let slope: Float = -0.25 
    var planeNormal = SIMD3<Float>(0, 1, -slope)
    planeNormal = simd_normalize(planeNormal)
    
    // Para que o plano passe pelo Y threshold em z=0:
    // dot( (0, cutYThreshold, 0), normal ) = d
    let planeD = planeNormal.y * cutYThreshold
    let neckPlane = Plane(normal: planeNormal, d: planeD)
    
    var finalV = [VertexData]()
    var vertexMap = [VertexData: Int]()
    var finalFaces = [[Int]]()
    
    var wallFacesRemoved = 0
    var neckFacesRemoved = 0
    
    for face in faces {
        var poly = [VertexData]()
        var faceCentroid = SIMD3<Float>(0,0,0)
        for idx in face {
            let p = rawV[idx.v]
            let uv = rawVT.isEmpty ? SIMD2<Float>(0,0) : rawVT[idx.vt]
            let n = rawVN.isEmpty ? SIMD3<Float>(0,1,0) : rawVN[idx.vn]
            poly.append(VertexData(p: p, uv: uv, n: n))
            faceCentroid += p
        }
        faceCentroid /= Float(face.count)
        
        // Remoção radical da parede de fundo (Z muito negativo, longe da câmera)
        if faceCentroid.z < -cylinderRadius {
            wallFacesRemoved += 1
            continue
        }
        
        let clipped = clipPolygon(poly, against: neckPlane)
        if clipped.isEmpty {
            neckFacesRemoved += 1
            continue
        }
        
        // Triangulate clipped polygon (fan)
        for i in 1..<(clipped.count - 1) {
            let pts = [clipped[0], clipped[i], clipped[i+1]]
            var faceIndices = [Int]()
            for pt in pts {
                if let idx = vertexMap[pt] {
                    faceIndices.append(idx)
                } else {
                    let newIdx = finalV.count
                    finalV.append(pt)
                    vertexMap[pt] = newIdx
                    faceIndices.append(newIdx)
                }
            }
            finalFaces.append(faceIndices)
        }
    }
    
    print("📊 Estatísticas do Corte Reto (Geométrico):")
    print("   - Parede de Fundo: \\(wallFacesRemoved) faces removidas.")
    print("   - Pescoço/Corpo: \\(neckFacesRemoved) faces removidas.")
    
    // Salvar novo OBJ
    var outLines = ["# Apple ModelIO OBJ File: scan 4_cropped"]
    outLines.append(contentsOf: materialHeader)
    outLines.append("g submesh")
    
    for v in finalV { outLines.append("v \\(v.p.x) \\(v.p.y) \\(v.p.z)") }
    for v in finalV { outLines.append("vt \\(v.uv.x) \\(v.uv.y)") }
    for v in finalV { outLines.append("vn \\(v.n.x) \\(v.n.y) \\(v.n.z)") }
    
    for f in finalFaces {
        let i0 = f[0] + 1; let i1 = f[1] + 1; let i2 = f[2] + 1
        outLines.append("f \\(i0)/\\(i0)/\\(i0) \\(i1)/\\(i1)/\\(i1) \\(i2)/\\(i2)/\\(i2)")
    }
    
    try outLines.joined(separator: "\\n").write(to: croppedURL, atomically: true, encoding: .utf8)
    print("✅ SUCESSO! Corte geométrico reto aplicado perfeitamente.")
    print("👉 Arquivo OBJ final salvo em: \\(croppedURL.path)")
    
SWIFT

# Replace from "print("✂️ Lendo OBJ original" to the end of the first do-catch try outputLines block.
# We will use string manipulation in ruby.
start_idx = content.index('print("✂️ Lendo OBJ original')
end_idx = content.index('    // 6. Converter o novo OBJ para USDC')

new_content = content[0...start_idx] + new_engine + "    " + content[end_idx..-1]

File.write(file, new_content)
puts "Script reescrito para Planar Clipping com sucesso!"
