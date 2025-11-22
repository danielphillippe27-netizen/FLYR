import SwiftUI
import MapboxMaps
import CoreLocation

// MARK: - Campaign Detail Map View

/// Map view for campaign details with building polygon support
struct CampaignDetailMap: View {
    let campaignId: UUID
    let addresses: [CampaignAddress]
    
    @StateObject private var buildings: UseCampaignBuildings
    
    init(campaignId: UUID, addresses: [CampaignAddress]) {
        self.campaignId = campaignId
        self.addresses = addresses
        
        // Initialize the buildings hook
        _buildings = StateObject(wrappedValue: UseCampaignBuildings(
            campaignId: campaignId,
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
        MapboxViewContainer(
            featureCollection: buildings.featureCollection,
            centerCoordinate: centerCoordinate,
            zoomLevel: 15
        )
        .frame(maxWidth: .infinity)
        .frame(height: 340) // Give it explicit height to avoid {64,64} warnings
        .task {
            print("🏢 [DETAIL MAP] Starting building fetch for campaign \(campaignId)")
            print("🏢 [DETAIL MAP] Addresses to process: \(addresses.count)")
            
            // Kick off fetch (tilequery -> upsert -> fetch FC)
            await buildings.fetchMissingBuildings()
        }
        .onChange(of: buildings.featureCollection) { featureCollection in
            guard let featureCollection = featureCollection else { 
                print("🏢 [DETAIL MAP] No feature collection to update")
                return 
            }
            
            print("🏢 [DETAIL MAP] Feature collection updated: \(featureCollection.features.count) features")
            MapboxBridge.shared.updatePolygons(featureCollection)
        }
        .onChange(of: buildings.isLoading) { isLoading in
            if isLoading {
                print("🏢 [DETAIL MAP] Building fetch started")
            } else {
                print("🏢 [DETAIL MAP] Building fetch completed")
            }
        }
        .onChange(of: buildings.error) { error in
            if let error = error {
                print("❌ [DETAIL MAP] Building fetch error: \(error)")
            }
        }
    }
}
