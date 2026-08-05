import SwiftUI

/// Redesigned Print QR Codes view - displays QR Sets instead of Campaigns
struct QRPrintViewV2: View {
    @StateObject private var hook = UseQRPrintV2()
    @State private var selectedSetId: UUID?
    @State private var showExportSheet = false
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Print QR Codes")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Select a QR Set")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                
                // QR Sets Display
                if hook.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hook.qrSets.isEmpty {
                    EmptyState(
                        illustration: "qrcode",
                        title: "No QR Sets",
                        message: "Create a QR set to get started with printing"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 150), spacing: 16)
                            ],
                            spacing: 16
                        ) {
                            ForEach(hook.qrSets) { qrSet in
                                QRSetCardView(qrSet: qrSet) {
                                    selectedSetId = qrSet.id
                                    showExportSheet = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Print QR Codes")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await hook.loadQRSets()
        }
        .sheet(isPresented: $showExportSheet) {
            if let setId = selectedSetId {
                QRExportOptionsSheet(
                    qrSetId: setId,
                    qrSetName: hook.qrSets.first(where: { $0.id == setId })?.name ?? "QR Set",
                    onDismiss: {
                        showExportSheet = false
                        selectedSetId = nil
                    }
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { hook.errorMessage != nil },
            set: { if !$0 { hook.errorMessage = nil } }
        )) {
            Button("OK") {
                hook.errorMessage = nil
            }
        } message: {
            if let error = hook.errorMessage {
                Text(error)
            }
        }
    }
}

