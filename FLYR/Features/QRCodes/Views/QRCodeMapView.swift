import SwiftUI
import Combine
import MapboxMaps
import CoreLocation

/// Map view showing QR codes for campaigns
struct QRCodeMapView: View {
    @StateObject private var hook = UseQRCodeMap()
    @State private var selectedCampaignId: UUID?
    @State private var mapView: MapView?
    
    var body: some View {
        ZStack {
            // Map
            if let mapView = mapView {
                MapboxMapViewRepresentable(
                    mapView: mapView,
                    mode: .light,
                    campaignPolygon: nil,
                    campaignId: selectedCampaignId
                )
                .ignoresSafeArea()
            } else {
                Color(.systemBackground)
                    .onAppear {
                        initializeMap()
                    }
            }
            
            // Campaign Selector Overlay
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if hook.isLoadingCampaigns {
                            ProgressView()
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(12)
                        } else {
                            Menu {
                                ForEach(hook.campaigns) { campaign in
                                    Button(action: {
                                        selectedCampaignId = campaign.id
                                        Task {
                                            await hook.loadQRCodesForCampaign(campaign.id)
                                            updateMapMarkers()
                                        }
                                    }) {
                                        HStack {
                                            Text(campaign.name)
                                            if selectedCampaignId == campaign.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.red)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            }
                        }
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .navigationTitle("QR Code Map")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await hook.loadCampaigns()
        }
        .onChange(of: hook.qrCodes) { _, _ in
            updateMapMarkers()
        }
    }
    
    private func initializeMap() {
        // Initialize map view
        let options = MapInitOptions()
        let mv = MapView(frame: .zero, mapInitOptions: options)
        
        // Load custom light style
        mv.mapboxMap.loadStyle(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        
        mapView = mv
    }
    
    private func updateMapMarkers() {
        guard let mapView = mapView else { return }
        
        // Add markers for each QR code location
        // This is a simplified version - in production you'd want to use Mapbox annotations
        for qrCode in hook.qrCodes {
            if let coordinate = qrCode.coordinate {
                // Add marker to map
                // Implementation would use Mapbox SDK to add point annotations
            }
        }
    }
}

/// View model for QR code map view
@MainActor
final class UseQRCodeMap: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var qrCodes: [QRCodeAddress] = []
    @Published var isLoadingCampaigns = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let api = QRCodeAPI.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        errorMessage = nil
        defer { isLoadingCampaigns = false }
        
        do {
            campaigns = try await api.fetchCampaigns()
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [QR Map] Error loading campaigns: \(error)")
        }
    }
    
    func loadQRCodesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            qrCodes = try await api.fetchQRCodesForCampaign(campaignId: campaignId)
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Map] Error loading QR codes: \(error)")
        }
    }
}

