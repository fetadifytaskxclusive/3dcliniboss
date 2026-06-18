import Foundation

struct Vertex: Hashable {
    var x: Float, y: Float, z: Float
}

struct Face {
    var v1: Int, v2: Int, v3: Int
    // keeping raw string to output easily if needed, but we need indices
    var raw: String
}

struct Edge: Hashable {
    var v1: Int
    var v2: Int
    init(_ a: Int, _ b: Int) {
        self.v1 = min(a, b)
        self.v2 = max(a, b)
    }
}

let objPath = "/Users/joaopaulogaldinodealencar/Downloads/scan 4.obj"
let content = try! String(contentsOfFile: objPath)
let lines = content.components(separatedBy: .newlines)

var vertices = [Vertex]() // 0-indexed in array, 1-indexed in OBJ
var originalLines = [String]()
var faces = [Face]()

for line in lines {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("v ") {
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        vertices.append(Vertex(x: Float(parts[1])!, y: Float(parts[2])!, z: Float(parts[3])!))
    } else if trimmed.hasPrefix("f ") {
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 4 {
            let v1 = Int(parts[1].components(separatedBy: "/")[0])!
            let v2 = Int(parts[2].components(separatedBy: "/")[0])!
            let v3 = Int(parts[3].components(separatedBy: "/")[0])!
            faces.append(Face(v1: v1, v2: v2, v3: v3, raw: trimmed))
        }
    }
}

print("Loaded \(vertices.count) vertices and \(faces.count) faces.")

// BFS para Connected Components
var adj = [Int: [Int]]()
for (i, face) in faces.enumerated() {
    adj[face.v1, default: []].append(i)
    adj[face.v2, default: []].append(i)
    adj[face.v3, default: []].append(i)
}

var visitedFaces = Set<Int>()
var clusters = [[Int]]()

for i in 0..<faces.count {
    if !visitedFaces.contains(i) {
        var cluster = [Int]()
        var queue = [i]
        visitedFaces.insert(i)
        var head = 0
        while head < queue.count {
            let curr = queue[head]
            head += 1
            cluster.append(curr)
            let f = faces[curr]
            for v in [f.v1, f.v2, f.v3] {
                for neighborFace in adj[v, default: []] {
                    if !visitedFaces.contains(neighborFace) {
                        visitedFaces.insert(neighborFace)
                        queue.append(neighborFace)
                    }
                }
            }
        }
        clusters.append(cluster)
    }
}

clusters.sort { $0.count > $1.count }
print("Found \(clusters.count) clusters. Largest has \(clusters[0].count) faces.")
