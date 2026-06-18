require 'fileutils'

file = "/Users/joaopaulogaldinodealencar/Downloads/test_cropper.swift"
content = File.read(file)

# Vamos substituir toda a parte 5 (Filtrar vértices) por uma versão mais inteligente
novo_filtro = <<-CODE
// 5. Filtrar vértices do OBJ
print("✂️ Lendo OBJ original para aplicar a guilhotina...")
guard FileManager.default.fileExists(atPath: objURL.path) else {
    exit(1)
}

do {
    let content = try String(contentsOf: objURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
    
    // PRIMEIRA PASSAGEM: Descobrir os limites reais da cabeça no eixo Z
    var maxZ: Float = -9999.0 // Frente do rosto (Nariz)
    var minZ: Float = 9999.0  // Trás da cabeça (Nuca)
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v ") {
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 4, let y = Float(parts[2]), let z = Float(parts[3]) {
                // Apenas olhar os vértices que estão na altura do rosto para achar o nariz e a nuca
                if y > cutYThreshold && y < (cutYThreshold + 0.3) {
                    if z > maxZ { maxZ = z }
                    if z < minZ { minZ = z }
                }
            }
        }
    }
    
    print("📏 Z Máximo (Frente): \\(maxZ), Z Mínimo (Trás): \\(minZ)")
    
    // Agora configuramos a inclinação (Slope)
    // O usuário quer que o corte seja mais alto na nuca e mais baixo na frente.
    // Isso significa que Y_cut deve ser MAIOR no minZ (nuca) e MENOR no maxZ (frente).
    // Exemplo: queremos que a nuca seja cortada 15 centímetros (0.15 unidades) MAIS ALTO que o queixo.
    let heightDiff: Float = 0.20 // 20cm mais alto na nuca
    let zSpan = maxZ - minZ
    let slope = zSpan > 0 ? (heightDiff / zSpan) : 0.0 // Positivo, porque queremos que quanto menor o Z (nuca), maior o Y!
    
    var keptVertexIndices = Set<Int>()
    var oldToNewIndex = [Int: Int]()
    var newIndex = 1
    var vertexIndex = 0
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v ") {
            vertexIndex += 1
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                
                let dx = x - faceCenterX
                let distanceFromCenterX = abs(dx)
                
                // Cálculo do corte inclinado:
                // maxZ é a frente (ex: 0.3), minZ é a nuca (ex: -0.3).
                // Distância do nariz para trás: (maxZ - z)
                // Quanto mais para trás (menor Z), maior a distância, logo somamos no YThreshold para o corte subir!
                let adjustedYThreshold = cutYThreshold + ((maxZ - z) * slope)
                
                // Radial: Filtra tudo que for mais largo que 1.2x o raio (ombros distantes)
                // e filtra a parede (z muito menor que a nuca)
                if y >= adjustedYThreshold && distanceFromCenterX <= cylinderRadius {
                    if z >= (minZ - 0.1) { // Só aceita até 10cm atrás da nuca (corta a parede)
                        keptVertexIndices.insert(vertexIndex)
                        oldToNewIndex[vertexIndex] = newIndex
                        newIndex += 1
                    }
                }
            }
        }
    }
    print("📊 Dos \\(vertexIndex) vértices, \\(keptVertexIndices.count) ficaram acima do pescoço.")
CODE

content.sub!(/\/\/ 5\. Filtrar vértices do OBJ.*print\("📊 Dos \\(vertexIndex\) vértices, \\(keptVertexIndices\.count\) ficaram acima do pescoço\."\)/m, novo_filtro)

File.write(file, content)
