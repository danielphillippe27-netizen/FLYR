import SwiftUI
import CoreLocation

struct QRCodeGeneratorView: View {
    @StateObject private var viewModel = QRCodeGeneratorViewModel()
    @State private var selectedSource: AddressSource = .campaign
    @State private var selectedCampaignId: UUID?
    @State private var selectedFarmId: UUID?
    @State private var showingQRDetail: QRCodeAddress?
    
    enum AddressSource: String, CaseIterable {
        case campaign = "Campaign"
        case farm = "Farm"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Source selector
                Picker("Source", selection: $selectedSource) {
                    ForEach(AddressSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedSource) { _, _ in
                    selectedCampaignId = nil
                    selectedFarmId = nil
                    viewModel.clearAddresses()
                }
                
                // Campaign/Farm selector
                if selectedSource == .campaign {
                    campaignSelector
                } else {
                    farmSelector
                }
                
                Divider()
                
                // Address list and QR codes
                if viewModel.isLoading {
                    ProgressView("Loading addresses...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.qrCodes.isEmpty {
                    emptyState
                } else {
                    qrCodeGrid
                }
            }
            .navigationTitle("Generate QR Codes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.qrCodes.isEmpty {
                        Button("Share All") {
                            viewModel.shareAllQRCodes()
                        }
                    }
                }
            }
            .sheet(item: $showingQRDetail) { qrCode in
                QRCodeDetailView(qrCode: qrCode)
            }
        }
    }
    
    // MARK: - Campaign Selector
    
    private var campaignSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Campaign")
                .font(.headline)
                .padding(.horizontal)
            
            if viewModel.isLoadingCampaigns {
                ProgressView()
                    .padding()
            } else if viewModel.campaigns.isEmpty {
                Text("No campaigns available")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.campaigns) { campaign in
                            QRCodeCampaignCard(
                                campaign: campaign,
                                isSelected: selectedCampaignId == campaign.id
                            ) {
                                selectedCampaignId = campaign.id
                                Task {
                                    await viewModel.loadAddressesForCampaign(campaign.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .task {
            await viewModel.loadCampaigns()
        }
    }
    
    // MARK: - Farm Selector
    
    private var farmSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Farm")
                .font(.headline)
                .padding(.horizontal)
            
            Text("Farm selection coming soon")
                .foregroundStyle(.secondary)
                .padding()
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("No QR Codes Generated")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Select a campaign to generate QR codes for its addresses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - QR Code Grid
    
    private var qrCodeGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.qrCodes) { qrCode in
                    QRCodeCard(qrCode: qrCode) {
                        showingQRDetail = qrCode
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Campaign Card

struct QRCodeCampaignCard: View {
    let campaign: CampaignListItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let count = campaign.addressCount {
                    Text("\(count) addresses")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                } else {
                    Text("Tap to load")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(width: 150)
            .padding()
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QR Code Card
// Note: QRCodeCard is now in Components/QRCodeCard.swift
// This old view uses the component from there

// MARK: - QR Code Detail View
// Note: QRCodeDetailView and LinkRow are now in Components/QRCodeDetailView.swift
// This old view uses the components from there

