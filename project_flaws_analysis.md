# Análise de Falhas do Projeto: SceneDepthPointCloud

Este documento descreve as principais falhas técnicas e de arquitetura identificadas no projeto, focando especificamente no pipeline de escaneamento 3D, recorte e upload de modelos.

---

## 1. Bug Crítico de Mutação de Coleção em SceneKit

No método `loadModelIntoScene` em [ModelCropper.swift], o código tenta agrupar todos os nós filhos sob um nó wrapper para calcular o bounding box:

```swift
let wrapperNode = SCNNode()
for child in scene.rootNode.childNodes {
    wrapperNode.addChildNode(child)
}
```

### A Falha
No SceneKit, adicionar um nó a um novo pai (`wrapperNode.addChildNode(child)`) remove-o implicitamente do pai original (`scene.rootNode`). Como `scene.rootNode.childNodes` é uma coleção que sofre mutação dinâmica, modificá-la durante o loop de iteração faz com que o iterador pule elementos (aproximadamente metade dos nós filhos são ignorados).

### Consequência
O modelo 3D carregado para o snapshot fica incompleto ou totalmente vazio, resultando em falhas de renderização e posterior falha na detecção facial.


---

## 2. Baixa Robustez na Detecção Facial via Vision API

A lógica de recorte do modelo depende de um snapshot ortográfico 2D off-screen para detectar rostos e calcular a altura de corte:

```swift
let cutYNormalized = try detectFaceAndComputeCutLine(in: snapshot)
```

### A Falha
1. **Problemas de Contraste:** O snapshot é renderizado com um fundo branco puro (`scene.background.contents = UIColor.white`) e alta iluminação ambiente. Se o modelo 3D tiver texturas claras ou cores neutras, a falta de sombreamento ou contraste dificulta a identificação dos limites faciais pelo `VNDetectFaceLandmarksRequest`, resultando no erro `faceNotFound`.
2. **Dependência de Orientação:** A posição da câmera assume que o rosto está voltado diretamente para o eixo Z. Se o escaneamento estiver rotacionado (por exemplo, de lado ou de cabeça para baixo), o snapshot não mostrará um rosto frontal, fazendo com que a detecção falhe.
3. **Fallback Silencioso:** Quando a detecção facial falha, o pipeline reverte silenciosamente para retornar o modelo original não recortado. Em um contexto clínico, isso resulta no upload de paredes de fundo ou malhas de torso ruidosas para o banco de dados.

---

## 3. Conversão Local Ineficiente de Arquivos 3D via WebView

Para converter modelos `OBJ` em `GLB` localmente, o aplicativo instancia uma `WKWebView` off-screen e carrega os arquivos do `Three.js`:

```swift
webView.loadHTMLString(htmlSource, baseURL: URL(string: "http://localhost"))
```

### A Falha
1. **Gargalos de Memória e Desempenho:** Processar malhas 3D complexas em JavaScript dentro de uma WebView no iOS é extremamente pesado e propenso a travamentos por falta de memória (OOM) em dispositivos com hardware limitado.
2. **Sobrecarga de Serialização Base64:** O buffer binário do GLB convertido é serializado como uma string Base64 no JS para ser enviado pela ponte nativa (`WKScriptMessageHandler`) e depois decodificado de volta em `Data` no Swift. Isso dobra a alocação de memória necessária durante a exportação.


---

## 4. Bloqueio de Thread do GCD com Semáforos Síncronos

Dentro de [ModelCropper.swift], as requisições assíncronas do Vision utilizam semáforos para bloquear a execução:

```swift
let semaphore = DispatchSemaphore(value: 0)
// ... executa requisição assíncrona ...
semaphore.wait()
```

### A Falha
Bloquear threads de background usando `semaphore.wait()` em filas do GCD pode levar à saturação de threads (starvation) no pool de execução se múltiplos escaneamentos ou arquivos forem processados simultaneamente, impactando a fluidez geral do app.

---

## 5. Leitura de Arquivo OBJ com Alto Consumo de Memória

Em [ModelCropper.swift], o motor de recorte lê o arquivo OBJ inteiro como uma única string UTF-8:

```swift
let content = try String(contentsOf: originalURL, encoding: .utf8)
let lines = content.components(separatedBy: .newlines)
```

### A Falha
Para escaneamentos de alta densidade (acima de 50MB–100MB), carregar todo o arquivo na memória e aplicar quebras de string gera picos de memória excessivos e sobrecarga na CPU.

---

## 6. Inconsistência entre Logs e Configurações Reais

Em [ReconstructionView.swift]:

```swift
print(" [3D_Engine] Iniciando PhotogrammetrySession (Config: Sequencial, Masking=true)...")
```

No entanto, o objeto de configuração real desativa o mascaramento do objeto:

```swift
config.isObjectMaskingEnabled = false
```

Esta inconsistência torna o log e o processo de depuração confusos sobre o comportamento real da sessão.
