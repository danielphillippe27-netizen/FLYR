import SwiftUI

struct LandingPageQRCodesView: View {
    let campaignId: UUID
    let landingPageId: UUID
    
    @StateObject private var viewModel = LandingPageQRCodesViewModel()
    @State private var showVariantPicker = false
    @State private var selectedQRForVariant: QRCode?
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView("Loading QR codes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Linked QR Codes Section
                        if !viewModel.linkedQRCodes.isEmpty {
                            linkedQRCodesSection
                        }
                        
                        // Available QR Codes Section
                        if !viewModel.availableQRCodes.isEmpty {
                            availableQRCodesSection
                        }
                        
                        // Empty State
                        if viewModel.linkedQRCodes.isEmpty && viewModel.availableQRCodes.isEmpty {
                            EmptyState(
                                illustration: "qrcode",
                                title: "No QR Codes",
                                message: "No QR codes found for this campaign"
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Manage QR Codes")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadQRCodes(campaignId: campaignId, landingPageId: landingPageId)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .confirmationDialog("Select Variant", isPresented: $showVariantPicker, presenting: selectedQRForVariant) { qrCode in
            Button("Variant A") {
                Task {
                    await viewModel.linkQR(qrCode, landingPageId: landingPageId, variant: "A")
                }
            }
            Button("Variant B") {
                Task {
                    await viewModel.linkQR(qrCode, landingPageId: landingPageId, variant: "B")
                }
            }
            Button("Cancel", role: .cancel) {
                selectedQRForVariant = nil
            }
        }
    }
    
    // MARK: - Linked QR Codes Section
    
    private var linkedQRCodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Linked QR Codes")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.text)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160), spacing: 20)
            ], spacing: 20) {
                ForEach(viewModel.linkedQRCodes) { qrCode in
                    QRCard(
                        qr: qrCode,
                        onUnlink: {
                            Task {
                                await viewModel.unlinkQR(qrCode)
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - Available QR Codes Section
    
    private var availableQRCodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available QR Codes")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.text)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160), spacing: 20)
            ], spacing: 20) {
                ForEach(viewModel.availableQRCodes) { qrCode in
                    QRCard(
                        qr: qrCode,
                        onLink: {
                            // Show variant picker
                            selectedQRForVariant = qrCode
                            showVariantPicker = true
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 10)
        }
    }
}


