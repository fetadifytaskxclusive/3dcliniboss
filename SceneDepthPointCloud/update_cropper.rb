require 'fileutils'

file = "/Users/joaopaulogaldinodealencar/Downloads/test_cropper.swift"
content = File.read(file)

# 1. Obter o X center do rosto em 3D
vision_block = <<-CODE
    let chinYNormalized = Float(face.boundingBox.origin.y)
    let faceHeightNormalized = Float(face.boundingBox.size.height)
    let faceWidthNormalized = Float(face.boundingBox.size.width)
    let faceMidXNormalized = Float(face.boundingBox.midX)
    
    let cutLineNormalized = chinYNormalized - (faceHeightNormalized * 0.35)
    
    let renderedMinY = Float(center.y) - Float(camera.orthographicScale)
    let renderedMaxY = Float(center.y) + Float(camera.orthographicScale)
    let totalRenderedHeight = renderedMaxY - renderedMinY
    
    let renderedMinX = Float(center.x) - Float(camera.orthographicScale)
    let totalRenderedWidth = totalRenderedHeight // A tela é 1024x1024 (quadrada), logo orthographic cobriu isso
    
    cutYThreshold = renderedMinY + (cutLineNormalized * totalRenderedHeight)
    let faceCenterX = renderedMinX + (faceMidXNormalized * totalRenderedWidth)
    let faceWidth3D = faceWidthNormalized * totalRenderedWidth
    
    // O raio do cilindro será 1.5x a largura do rosto para garantir que pega a nuca e o cabelo, mas corta a parede!
    let cylinderRadius = faceWidth3D * 1.6
    
    print("✅ Rosto encontrado!")
    print("   - Threshold Y base: \\(cutYThreshold)")
    print("   - Centro X do rosto: \\(faceCenterX)")
    print("   - Raio do cilindro de corte: \\(cylinderRadius)")
CODE

content.sub!(/let chinYNormalized =.*print\("✅ Rosto encontrado! Threshold Y de corte: \\(cutYThreshold\)"\)/m, vision_block)

# 2. Modificar o loop de vértices para incluir corte cilíndrico e corte inclinado
vertex_loop = <<-CODE
            if parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                // 1. Corte Cilíndrico (Radial) para remover a parede de fundo
                // Assumimos que o Z center da cabeça está próximo de 0 ou um pouco atrás do rosto
                // Como não temos a profundidade exata do rosto, faremos um raio relaxado no eixo Z, 
                // centrado no eixo X do rosto.
                let dx = x - faceCenterX
                // A parede costuma estar longe no Z (positivo ou negativo dependendo da câmera).
                // Vamos usar um cilindro que engloba a largura da cabeça.
                let distanceFromCenterX = abs(dx)
                
                // 2. Corte Inclinado do Pescoço
                // No SceneKit/ARKit, a câmera olha para -Z. A face do rosto costuma estar voltada para +Z.
                // Isso significa que a nuca tem um Z menor que o rosto.
                // Queremos que o corte suba na parte de trás (nuca).
                // Inclinação: y = base_y + (z * slope)
                // Se a face está voltada para +Z (ou a câmera está em +Z), vamos testar um slope que levanta a parte de trás.
                let slope: Float = 0.45 // Inclinação de aprox 25 graus
                let adjustedYThreshold = cutYThreshold + (z * slope)
                
                if y >= adjustedYThreshold && distanceFromCenterX <= cylinderRadius {
                    // Para o eixo Z, também cortamos o que estiver absurdamente longe (parede)
                    if abs(z) < (cylinderRadius * 1.5) {
                        keptVertexIndices.insert(vertexIndex)
                        oldToNewIndex[vertexIndex] = newIndex
                        newIndex += 1
                    }
                }
            }
CODE

content.sub!(/if parts.count >= 4, let y = Float\(parts\[2\]\) \{\s+if y >= cutYThreshold \{\s+keptVertexIndices.insert\(vertexIndex\)\s+oldToNewIndex\[vertexIndex\] = newIndex\s+newIndex \+= 1\s+\}\s+\}/m, vertex_loop)

# 3. Injecar as variaveis no topo do do-catch do loop
content.sub!(/var keptVertexIndices = Set<Int>\(\)/, "var keptVertexIndices = Set<Int>()\n    // variaveis extraidas\n    let faceCenterX = Float(center.x) // fallback\n    let cylinderRadius: Float = 1000.0 // fallback\n")

# Para passar as variaveis do escopo do Vision para o escopo do OBJ
content.sub!(/var cutYThreshold: Float = -999.0/, "var cutYThreshold: Float = -999.0\nvar faceCenterX: Float = 0.0\nvar cylinderRadius: Float = 0.0")

# Corrigir o fallback que injetei incorretamente no passo 3
content.sub!(/var keptVertexIndices = Set<Int>\(\)\n    \/\/ variaveis extraidas\n    let faceCenterX = Float\(center.x\) \/\/ fallback\n    let cylinderRadius: Float = 1000.0 \/\/ fallback/, "var keptVertexIndices = Set<Int>()")
content.sub!(/let faceCenterX = renderedMinX/, "faceCenterX = renderedMinX")
content.sub!(/let cylinderRadius = faceWidth3D/, "cylinderRadius = faceWidth3D")

File.write(file, content)
puts "Script atualizado com corte inclinado e cilíndrico!"
