import SwiftUI

@available(iOS 17.0, *)
struct ScanSelectionView: View {
    @EnvironmentObject var bridgeManager: WebBridgeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Fundo Metade Acqua Metade Branco
                VStack(spacing: 0) {
                    AppConfig.cliniBossPrimary
                        .frame(height: 250)
                        .ignoresSafeArea(edges: .top)
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea(edges: .bottom)
                }
                
                VStack(spacing: 0) {
                    // Header Area (Acqua)
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Módulo 3D")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            
                        Text("Selecione qual parte será escaneada.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                    
                    // Card Area (Branco)
                    VStack(spacing: 24) {
                        Text("Tipo de Scan")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                        
                        NavigationLink(destination: CaptureView(isHeadScan: true)) {
                            HStack(spacing: 12) {
                                Image(systemName: "face.smiling")
                                    .font(.title2)
                                Text("Cabeça / Rosto")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppConfig.cliniBossPrimary)
                            .clipShape(Capsule())
                        }
                        
                        NavigationLink(destination: ExperimentalCaptureView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.stand")
                                    .font(.title2)
                                Text("Corpo Inteiro")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppConfig.cliniBossPrimary)
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if let req = bridgeManager.currentRequest {
                                bridgeManager.sendCancelResult(requestId: req.requestId ?? "")
                            }
                            bridgeManager.isScanning = false
                            dismiss()
                        }) {
                            Text("Cancelar Escaneamento")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .padding()
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(30)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(35)
                    .offset(y: -40)
                }
            }
        }
    }
}
