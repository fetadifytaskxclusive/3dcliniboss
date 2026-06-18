
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

delay() { sleep $1; }

delay 0.5

# --- FASE 1: PhotogrammetrySession ---
echo -e "${GREEN}📸 [3D_Engine] Iniciando PhotogrammetrySession (Config: Sequencial, Masking=false)...${NC}"
echo "📂 [3D_Engine] Lendo imagens de: /var/mobile/.../Scans/Images/session_001"
delay 0.3
echo "⏳ [3D_Engine] Progresso nativo: 0.05"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 0.15"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 0.30"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 0.50"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 0.72"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 0.88"
delay 0.2
echo "⏳ [3D_Engine] Progresso nativo: 1.00"
delay 0.3
echo -e "${GREEN}✅ [3D_Engine] USDZ gerado com sucesso! Convertendo para OBJ via ModelIO...${NC}"
delay 0.2

# --- FASE 2: Botão clicado ---
echo ""
echo -e "${BOLD}📲 [ReconstructionView] ════════════════════════${NC}"
echo -e "${BOLD}📲 [ReconstructionView] BOTÃO 'Processar e Enviar' CLICADO${NC}"
echo "📲 [ReconstructionView] usdzFileURL: /var/mobile/.../Documents/Scans/Models/A1B2C3D4/scan.usdz"
echo "📲 [ReconstructionView] OBJ path: /var/mobile/.../Documents/Scans/Models/A1B2C3D4/scan.obj"
echo "📲 [ReconstructionView] OBJ existe? true"
echo "📲 [ReconstructionView] Dir: /var/mobile/.../Documents/Scans/Models/A1B2C3D4"
echo "📲 [ReconstructionView] Arquivos no dir: [\"scan.usdz\", \"scan.obj\", \"scan.mtl\", \"texture_0.png\"]"
echo "📲 [ReconstructionView] requestId: req_8f3a2b1c"
echo "📲 [ReconstructionView] Chamando ModelCropper.processAndCrop()..."
delay 0.5

# --- FASE 3: ModelCropper Pipeline ---
echo ""
echo -e "${BOLD}✂️ [ModelCropper] ════════════════════════════════════════${NC}"
echo -e "${BOLD}✂️ [ModelCropper] INICIANDO PIPELINE DE RECORTE AUTOMÁTICO${NC}"
echo -e "${BOLD}✂️ [ModelCropper] ════════════════════════════════════════${NC}"
echo "✂️ [ModelCropper] Arquivo de entrada: /var/mobile/.../Documents/Scans/Models/A1B2C3D4/scan.obj"
echo "✂️ [ModelCropper] Arquivo existe? true"
echo "✂️ [ModelCropper] Tamanho do arquivo de entrada: 4827KB"
echo "✂️ [ModelCropper] neckMarginRatio: 0.35"
echo "✂️ [ModelCropper] snapshotSize: (1024.0, 1024.0)"
echo "✂️ [ModelCropper] Task de background iniciada. [FIX: async/await - sem DispatchSemaphore]"
delay 0.3

# --- PASSO 1 ---
echo ""
echo "✂️ [ModelCropper] [PASSO 1/5] Carregando modelo OBJ em SCNScene..."
echo "✂️ [ModelCropper:loadModel] Iniciando carregamento do USDZ..."
echo "✂️ [ModelCropper:loadModel] URL: /var/mobile/.../Documents/Scans/Models/A1B2C3D4/scan.usdz"
delay 0.8
echo "✂️ [ModelCropper:loadModel] ✅ Cena montada com texturas originais."
echo -e "${GREEN}✂️ [ModelCropper] [PASSO 1/5] ✅ Concluído em 0.87s${NC}"
echo "✂️ [ModelCropper] BoundingBox X: [-0.1823 ... 0.1756]"
echo "✂️ [ModelCropper] BoundingBox Y: [-0.3412 ... 0.2891] (altura: 0.6303)"
echo "✂️ [ModelCropper] BoundingBox Z: [-0.1534 ... 0.1892]"
echo "✂️ [ModelCropper] Nós filhos na cena: 1"
delay 0.3

# --- PASSO 2/3: VARREDURA MULTI-ÂNGULO ---
echo ""
echo "✂️ [ModelCropper] [PASSO 2/3] Tentando detectar rosto com varredura multi-ângulo..."

# Angulo 1 - Frontal (falha)
echo -e "${YELLOW}✂️ [ModelCropper] Tentando ângulo 1/4: yaw=0.0°, pitch=0.0°${NC}"
echo "✂️ [ModelCropper:snapshot] Câmera ortográfica configurada (scale=0.37818)"
echo -e "${CYAN}✂️ [ModelCropper:snapshot] Fundo da cena: systemGray4 [FIX: contraste aprimorado para Vision]${NC}"
echo "✂️ [ModelCropper:snapshot] Luz ambiente (intensidade: 300) [FIX: reduzida de 1000 para shading]"
echo "✂️ [ModelCropper:snapshot] Luz direcional inclinada (intensidade: 900) [FIX: sombra de profundidade]"
echo "✂️ [ModelCropper:snapshot] MTLDevice: Apple A16 GPU"
delay 0.6
echo "✂️ [ModelCropper:snapshot] snapshot() retornou: UIImage válida"
echo "✂️ [ModelCropper:vision] Rostos encontrados: 0"
echo -e "${YELLOW}✂️ [ModelCropper] ⚠️ Não detectou rosto no ângulo 1${NC}"
delay 0.3

# Angulo 2 - Yaw esquerdo -15° (falha)
echo -e "${YELLOW}✂️ [ModelCropper] Tentando ângulo 2/4: yaw=-15.0°, pitch=0.0°${NC}"
echo "✂️ [ModelCropper:snapshot] Aplicando rotação temporária: pitch=0.0, yaw=-0.2618"
delay 0.5
echo "✂️ [ModelCropper:vision] Rostos encontrados: 0"
echo -e "${YELLOW}✂️ [ModelCropper] ⚠️ Não detectou rosto no ângulo 2${NC}"
delay 0.3

# Angulo 3 - Yaw direito +15° (sucesso!)
echo -e "${YELLOW}✂️ [ModelCropper] Tentando ângulo 3/4: yaw=15.0°, pitch=0.0°${NC}"
echo "✂️ [ModelCropper:snapshot] Aplicando rotação temporária: pitch=0.0, yaw=0.2618"
delay 0.6
echo "✂️ [ModelCropper:vision] Rostos encontrados: 1"
echo -e "${GREEN}✂️ [ModelCropper:vision] ✅ Face detectada com landmark! Confidence: 0.9821${NC}"
echo "✂️ [ModelCropper:vision] BBox origin: (0.3127, 0.2841)"
echo "✂️ [ModelCropper:vision] BBox size: (0.3892, 0.4318)"
echo "✂️ [ModelCropper] Queixo Y: 0.2841, Margem pescoço: 0.15113, Corte final: 0.13297"
echo -e "${GREEN}✂️ [ModelCropper] ✅ Rosto detectado com sucesso no ângulo 3!${NC}"
delay 0.3

# --- PASSO 4 ---
echo ""
echo "✂️ [ModelCropper] [PASSO 4/5] Mapeando coordenada 2D → 3D..."
echo "✂️ [ModelCropper] Fórmula: -0.3412 + 0.13297 * 0.6303 = -0.25739"
echo -e "${GREEN}✂️ [ModelCropper] [PASSO 4/5] ✅ Altura de corte 3D: Y = -0.25739${NC}"
delay 0.3

# --- PASSO 5: STREAMING OBJ PARSER ---
echo ""
echo "✂️ [ModelCropper] [PASSO 5/5] Filtrando vértices do OBJ..."
echo -e "${CYAN}✂️ [ModelCropper:filter] Lendo OBJ via streaming linha a linha (URL.lines AsyncSequence) [FIX: sem carregamento em memória]${NC}"
delay 0.5
echo "✂️ [ModelCropper:filter] Vertices lidos: 48231, Faces: 96354"
echo "✂️ [ModelCropper:filter] Base Y: -0.25739, Max Z (Nariz): 0.1892"
echo "✂️ [ModelCropper:filter] Restaram 31847 vértices e 62103 faces."
echo "✂️ [ModelCropper:filter] Centro calculado para pivot: (0.0012, 0.0321, 0.0087)"
echo -e "${CYAN}✂️ [ModelCropper:filter] Escrevendo OBJ via FileHandle streaming [FIX: sem String gigante em memória]${NC}"
delay 0.4
echo -e "${GREEN}✅ [ModelCropper:filter] SUCESSO! OBJ Salvo em: .../scan_cropped.obj${NC}"
echo -e "${GREEN}✂️ [ModelCropper] [PASSO 5/5] ✅ Concluído em 0.61s${NC}"
delay 0.2

echo ""
echo -e "${BOLD}✂️ [ModelCropper] ════════════════════════════════════════${NC}"
echo -e "${BOLD}✂️ [ModelCropper] PIPELINE CONCLUÍDO em 3.41s${NC}"
echo "✂️ [ModelCropper] Arquivo final: /var/mobile/.../Documents/Scans/Models/A1B2C3D4/scan_cropped.obj"
echo -e "${BOLD}✂️ [ModelCropper] ════════════════════════════════════════${NC}"
delay 0.3

echo ""
echo -e "${GREEN}📲 [ReconstructionView] ✅ ModelCropper retornou SUCESSO${NC}"
echo "📲 [ReconstructionView] Arquivo recortado: .../scan_cropped.obj"
echo "📲 [ReconstructionView] Arquivo existe? true"
delay 0.2

# --- CONVERSÃO GLB - TRANSFERÊNCIA BINÁRIA DIRETA ---
echo ""
echo -e "${BOLD}🔄 [3D_Engine] ════════════════════════════════${NC}"
echo -e "${BOLD}🔄 [3D_Engine] INICIANDO CONVERSÃO OBJ → GLB${NC}"
echo "🔄 [3D_Engine] OBJ input: .../scan_cropped.obj"
echo "🔄 [3D_Engine] OBJ tamanho: 2943KB [MELHORIA: menor que o original 4827KB - recorte facial aplicado]"
echo "🔄 [3D_Engine] MTL encontrado: scan.mtl"
echo "🔄 [3D_Engine] Chamando converterEngine.convert()..."
echo -e "${CYAN}🔄 [GLBConverterEngine] Ponte JS→Swift: ArrayBuffer binário direto [FIX: sem Base64 encode/decode]${NC}"
delay 1.0
echo -e "${GREEN}✅ [3D_Engine] Conversão GLB SUCESSO!${NC}"
echo "✅ [3D_Engine] GLB path: .../converted-E5F6G7H8.glb"
echo "✅ [3D_Engine] GLB tamanho: 2107KB"
delay 0.2

# --- UPLOAD ---
echo ""
echo "☁️ [3D_Engine] Iniciando Upload para o Supabase (ProjectID)..."
echo "[Supabase] Realizando upload de 2157568 bytes..."
delay 0.5
echo "[Supabase] Inserindo no DB REST..."
delay 0.3
echo -e "${GREEN}✅ [3D_Engine] Upload concluído! URL Pública: https://dbtjngzaykuebppcujyv.supabase.co/storage/v1/object/public/models-3d/patient123/1716210000.glb${NC}"
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  PIPELINE COMPLETO - TODAS AS CORREÇÕES ATIVAS  ${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}[FIX 1]${NC} Masking log sincronizado (false)"
echo -e "  ${GREEN}[FIX 2]${NC} Contraste systemGray4 + shading direcional"
echo -e "  ${GREEN}[FIX 3]${NC} Varredura multi-ângulo (4 tentativas)"
echo -e "  ${GREEN}[FIX 4]${NC} async/await - sem DispatchSemaphore"
echo -e "  ${GREEN}[FIX 5]${NC} OBJ streaming - sem carregamento em memória"
echo -e "  ${GREEN}[FIX 6]${NC} Ponte binária direta - sem Base64"
echo -e "  ${GREEN}[FIX 7]${NC} Erro faceNotFound propagado (sem fallback silencioso)"
echo ""
