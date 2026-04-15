import SwiftUI
import MapboxMaps
import CoreLocation

// MARK: - Campaign Detail View with Building Polygons

/// Main campaign detail view that shows the map with building polygons
struct CampaignDetailMapView: View {
    let campaign: CampaignV2
    let addresses: [CampaignAddress]   // contains formatted, postal_code, coord
    
    @StateObject private var buildings: UseCampaignBuildings
    
    init(campaign: CampaignV2, addresses: [CampaignAddress]) {
        self.campaign = campaign
        self.addresses = addresses
        
        // Initialize the buildings hook
        _buildings = StateObject(wrappedValue: UseCampaignBuildings(
            campaignId: campaign.id,
            addresses: addresses,
            token: Secrets.mapboxToken
        ))
    }
    
    // Calculate center coordinate from addresses
    private var centerCoordinate: CLLocationCoordinate2D? {
        // Find first address with coordinate
        if let firstAddress = addresses.first(where: { $0.coordinate != nil }),
           let coord = firstAddress.coordinate {
            return coord
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Campaign header
            VStack(alignment: .leading, spacing: 8) {
                Text(campaign.name)
                    .font(.flyrTitle2)
                    .fontWeight(.bold)
                
                Text("Type: \(campaign.type.rawValue)")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("\(addresses.count) addresses")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Map with building polygons
            MapboxViewContainer(
                featureCollection: buildings.featureCollection,
                centerCoordinate: centerCoordinate,
                zoomLevel: 15
            )
            .frame(maxWidth: .infinity)
            .frame(height: 360)            // 👈 kills the 64x64 error
                .task {
                    print("🏗️ [HOOK] fetchMissingBuildings for \(campaign.name)")
                    print("🏗️ [HOOK] Processing \(addresses.count) addresses")
                    
                    await buildings.fetchMissingBuildings()
                    
                    print("🏗️ [HOOK] featureCollection count = \(buildings.featureCollection?.features.count ?? 0)")
                }
                .onChange(of: buildings.featureCollection) { _, fc in
                    guard let fc else { return }
                    try? BuildingLayers.addOrUpdate(
                        map: MapboxBridge.shared.mapView!.mapboxMap,
                        sourceId: "campaign-buildings",
                        featureCollection: fc
                    )
                }
                .onChange(of: buildings.isLoading) { _, isLoading in
                    if isLoading {
                        print("🏗️ [HOOK] Building fetch started")
                    } else {
                        print("🏗️ [HOOK] Building fetch completed")
                    }
                }
                .onChange(of: buildings.error) { _, error in
                    if let error = error {
                        print("❌ [HOOK] Building fetch error: \(error)")
                    }
                }
            
            // Status indicator
            if buildings.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading building polygons...")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let error = buildings.error {
                Text("Error: \(error)")
                    .font(.flyrCaption)
                    .foregroundColor(.red)
                    .padding()
            } else if let featureCollection = buildings.featureCollection {
                Text("\(featureCollection.features.count) building polygons loaded")
                    .font(.flyrCaption)
                    .foregroundColor(.green)
                    .padding()
            }
        }
    }
}
