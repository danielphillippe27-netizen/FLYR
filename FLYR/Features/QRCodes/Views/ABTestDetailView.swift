import SwiftUI
import UIKit

/// A/B Test detail view
/// Shows experiment details, variants, stats, and actions
struct ABTestDetailView: View {
    @StateObject private var hook: UseABTestDetail
    @State private var showMarkWinnerSheet = false
    @State private var selectedWinnerVariantId: UUID?
    
    init(experimentId: UUID) {
        _hook = StateObject(wrappedValue: UseABTestDetail(experimentId: experimentId))
    }
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            if hook.isLoading {
                ProgressView("Loading experiment...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let experiment = hook.experiment {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Text(experiment.name)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)
                            
                            HStack {
                                ABTestStatusPill(status: experiment.status)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Variant Cards
                        VStack(spacing: 16) {
                            if let variantA = hook.variantA {
                                ABTestVariantCard(
                                    variant: variantA,
                                    onCopyURL: {
                                        copyToClipboard(variantA.fullURL)
                                    },
                                    onDownloadPNG: {
                                        downloadQRPNG(url: variantA.fullURL)
                                    }
                                )
                            }
                            
                            if let variantB = hook.variantB {
                                ABTestVariantCard(
                                    variant: variantB,
                                    onCopyURL: {
                                        copyToClipboard(variantB.fullURL)
                                    },
                                    onDownloadPNG: {
                                        downloadQRPNG(url: variantB.fullURL)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Stats Section
                        if let stats = hook.stats {
                            ABTestStatsCard(
                                stats: stats,
                                variantA: hook.variantA,
                                variantB: hook.variantB
                            )
                            .padding(.horizontal, 20)
                        } else if hook.isLoadingStats {
                            ProgressView("Loading statistics...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        
                        // Footer Actions
                        if experiment.status == "running" {
                            VStack(spacing: 12) {
                                Button {
                                    showMarkWinnerSheet = true
                                } label: {
                                    Text("Mark Winner")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color(hex: "FF4B47"))
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        } else if experiment.status == "completed", let winnerId = hook.winnerVariantId {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.green)
                                    
                                    Text("Winner: Variant \(hook.variantA?.id == winnerId ? "A" : "B")")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(12)
                                
                                Button {
                                    // TODO: Implement "Use Winner as Default QR"
                                } label: {
                                    Text("Use Winner as Default QR")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color(hex: "FF4B47"))
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .navigationTitle("A/B Test")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await hook.loadExperiment()
            await hook.loadStats()
        }
        .sheet(isPresented: $showMarkWinnerSheet) {
            MarkWinnerSheet(
                variantA: hook.variantA,
                variantB: hook.variantB,
                selectedVariantId: $selectedWinnerVariantId,
                onConfirm: {
                    if let variantId = selectedWinnerVariantId {
                        Task {
                            await hook.markWinner(variantId: variantId)
                            showMarkWinnerSheet = false
                        }
                    }
                },
                onCancel: {
                    showMarkWinnerSheet = false
                }
            )
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
    
    // MARK: - Actions
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
    
    private func downloadQRPNG(url: String) {
        // Find the root view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            ABTestQRGenerator.shareQRCodePNG(url: url, from: rootViewController)
        }
    }
}

// MARK: - Mark Winner Sheet

private struct MarkWinnerSheet: View {
    let variantA: ExperimentVariant?
    let variantB: ExperimentVariant?
    @Binding var selectedVariantId: UUID?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Select the winning variant")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 20)
                
                VStack(spacing: 12) {
                    if let variantA = variantA {
                        Button {
                            selectedVariantId = variantA.id
                        } label: {
                            HStack {
                                Text("Variant A")
                                    .font(.system(size: 17, weight: .medium))
                                Spacer()
                                if selectedVariantId == variantA.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "FF4B47"))
                                }
                            }
                            .padding()
                            .background(selectedVariantId == variantA.id ? Color(hex: "FF4B47").opacity(0.1) : Color.bgSecondary)
                            .cornerRadius(12)
                        }
                    }
                    
                    if let variantB = variantB {
                        Button {
                            selectedVariantId = variantB.id
                        } label: {
                            HStack {
                                Text("Variant B")
                                    .font(.system(size: 17, weight: .medium))
                                Spacer()
                                if selectedVariantId == variantB.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "FF4B47"))
                                }
                            }
                            .padding()
                            .background(selectedVariantId == variantB.id ? Color(hex: "FF4B47").opacity(0.1) : Color.bgSecondary)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Text("Confirm Winner")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(selectedVariantId != nil ? Color(hex: "FF4B47") : Color(.systemGray4))
                            .cornerRadius(12)
                    }
                    .disabled(selectedVariantId == nil)
                    
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Color(hex: "FF4B47"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.bgSecondary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Mark Winner")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        ABTestDetailView(experimentId: UUID())
    }
}

