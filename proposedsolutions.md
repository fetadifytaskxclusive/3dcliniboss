# Propostas de Solução para as Falhas do Projeto SceneDepthPointCloud

Este documento apresenta as soluções técnicas recomendadas para resolver os problemas identificados no documento de análise de falhas do projeto.

---

## 1. Solução para o Bug de Mutação de Coleção em SceneKit

### Problema
O SceneKit sofre mutação de coleção dinâmica concorrente ao tentar mover nós filhos iterando sobre `scene.rootNode.childNodes` diretamente.

### Solução Proposta
Criar uma cópia estática em array dos nós filhos antes de iterá-los. Dessa forma, a remoção implícita dos nós de `scene.rootNode` não interfere na iteração.

---

## 2. Solução para a Baixa Robustez na Detecção Facial via Vision API

### Problema
A detecção facial via snapshot 2D falha devido a falta de contraste no fundo branco puro, desalinhamento rotacional da câmera/modelo e falta de tratamento explícito de erro no pipeline.

### Solução Proposta
1. **Contraste de Fundo Aprimorado:** Alterar a cor de fundo do snapshot para um tom cinza neutro ou azulado contrastante com tons de pele/malha (`scene.background.contents = UIColor.systemGray4`). Ajustar a iluminação direcional para criar sombreamentos sutis de profundidade (ambient occlusion / shading), ajudando o Vision a identificar contornos faciais.
2. **Varredura Multi-Ângulo (Rotação de Fallback):** Caso o rosto não seja detectado na posição frontal padrão (Z normalizado), rotacionar o modelo ou a câmera em pequenos passos de ângulo (por exemplo, -15° a +15° no eixo Y e X) e re-tentar a detecção em até 3 snapshots adicionais antes de falhar.
3. **Tratamento de Erro e Alerta no App:** Desativar o fallback silencioso que realiza o upload do arquivo completo sem recorte em caso de falha. Propagar o erro `.faceNotFound` de forma clara para que o usuário clínico receba um alerta recomendando re-escanear o paciente sob melhores condições de enquadramento.

---

## 3. Solução para a Conversão Local Ineficiente de Arquivos 3D via WebView

### Problema
Conversão pesada de OBJ para GLB utilizando `WKWebView` off-screen rodando Three.js, com gargalos de serialização Base64 e alocação de memória no iOS.

### Solução Proposta
1. **Conversão Nativa com ModelIO:** Utilizar o framework nativo `ModelIO` para carregar o arquivo `.obj` e exportá-lo diretamente como `.usd` / `.usdz` ou usar bibliotecas nativas compiladas em C++/Swift (como um parser/gerador GLTF nativo leve) para fazer a conversão diretamente de binário para binário sem intermédio de ponte JavaScript.
2. **Otimização da Ponte (caso a WebView seja obrigatória):** Se a conversão via JavaScript for indispensável por conta de regras de negócio específicas, usar a transferência direta de dados binários do JS para o Swift via `WKWebView` (suportada nativamente no iOS 14+ via `ArrayBuffer` de mensagens), eliminando o custo de encode/decode de strings em Base64.

---

## 4. Solução para o Bloqueio de Thread do GCD com Semáforos Síncronos

### Problema
O uso de `DispatchSemaphore` bloqueia de maneira síncrona as threads do GCD para esperar o retorno das chamadas do Vision API, arriscando thread starvation sob carga de processamento concorrente.

### Solução Proposta
Substituir a lógica de semáforos legada pelo modelo moderno de concorrência cooperativa do Swift (`async/await`). Usar `withCheckedThrowingContinuation` para suspender assincronamente as tarefas sem prender a thread de execução do sistema.

---

## 5. Solução para a Leitura de Arquivo OBJ com Alto Consumo de Memória

### Problema
Carregar o arquivo OBJ inteiro como uma única string e particioná-lo com `components(separatedBy:)` consome muita memória RAM para malhas densas (acima de 50MB).

### Solução Proposta
Substituir o carregamento completo por leitura baseada em fluxo (*streaming*) linha a linha. Em Swift, podemos utilizar `InputStream` ou ler o arquivo através da API `URL.lines` do Swift moderno (usando `AsyncSequence`), processando e descartando cada linha da memória de forma sequencial.

---

## 6. Solução para a Inconsistência entre Logs e Configurações Reais

### Problema
O log de console no `ReconstructionView.swift` indica `Masking=true`, mas o código configura a sessão com `isObjectMaskingEnabled = false`.

### Solução Proposta
Sincronizar a configuração e a descrição de logs. A melhor prática é ler o valor diretamente do objeto de configuração gerado para compor a mensagem do log de forma dinâmica, evitando strings literais dessincronizadas.
