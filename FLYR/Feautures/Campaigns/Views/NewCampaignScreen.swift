import SwiftUI
import CoreHaptics
import CoreLocation

struct NewCampaignScreen: View {
    @ObservedObject var store: CampaignV2Store
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var type: CampaignType = .flyer
    @State private var tags = ""
    @State private var source: AddressSource = .closestHome
    @State private var count: AddressCountOption = .c100
    
    // closest-home state
    @State private var seedQuery = ""
    @StateObject private var addressHook = UseAddresses()
    @StateObject private var outlinesHook = UseBuildingOutlines()
    @StateObject private var auto = UseAddressAutocomplete()
    
    // map picker state
    @State private var showMapSeed = false
    @State private var seedLabel: String = ""
    @State private var selectedCenter: CLLocationCoordinate2D? = nil
    
    @StateObject private var createHook = UseCreateCampaign()
    
    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch source {
        case .closestHome: 
            return !addressHook.items.isEmpty
        case .map:
            return !addressHook.items.isEmpty
        case .sameStreet:
            return !addressHook.items.isEmpty
        case .importList:
            return false // Removed from UI
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                
                FormSection("Campaign") {
                    // Name field with consistent styling
                    HStack {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    FormRowMenuPicker("Type",
                                       options: CampaignType.ordered,
                                       selection: $type)
                    
                    // Tags field with consistent styling
                    HStack {
                        TextField("Tags (optional)", text: $tags)
                            .textInputAutocapitalization(.words)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .formContainerPadding()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Address")
                        .font(.headline)
                    
                    Text("How do you want to get addresses?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    SourceSegment(selected: $source)
                    
                    Group {
                        if source == .closestHome {
                            // AddressSearchField without the Map button
                            AddressSearchField(auto: auto) { suggestion in
                                selectedCenter = suggestion.coordinate
                                seedLabel = auto.query
                                auto.clear()   // ensure list is hidden after parent handles selection
                            }
                            
                            // Show current chosen seed (from text or map)
                            if !seedLabel.isEmpty {
                                Text(seedLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Count selection picker
                            FormRowMenuPicker("How many addresses?",
                                               options: AddressCountOption.allCases,
                                               selection: $count)
                            
                            // Source indicator
                            if !addressHook.items.isEmpty {
                                HStack {
                                    Image(systemName: "building.2")
                                        .foregroundStyle(.blue)
                                    Text("Address Database")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            PrimaryButton(
                                title: addressHook.isLoading ? "Searching…" : 
                                       (!addressHook.items.isEmpty ? "Found \(addressHook.items.count) Homes" : "Find \(count.rawValue) Nearby"),
                                enabled: (!auto.query.isEmpty || selectedCenter != nil) && !addressHook.isLoading,
                                style: !addressHook.items.isEmpty ? .success : .primary
                            ) {
                                if let c = selectedCenter {
                                    addressHook.fetchNearest(center: c, target: count.rawValue)
                                } else {
                                    // Forward geocode the query first
                                    Task {
                                        let geoAPI = GeoAPI.shared
                                        let seed = try await geoAPI.forwardGeocodeSeed(auto.query)
                                        addressHook.fetchNearest(center: seed.coordinate, target: count.rawValue)
                                    }
                                }
                            }
                            
                            if let err = addressHook.error {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        } else if source == .map {
                            // Map picker interface
                            Button {
                                showMapSeed = true
                            } label: {
                                HStack {
                                    Image(systemName: "map")
                                    Text(seedLabel.isEmpty ? "Select location on map" : seedLabel)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            if !seedLabel.isEmpty {
                                // Count selection picker
                                FormRowMenuPicker("How many addresses?",
                                                   options: AddressCountOption.allCases,
                                                   selection: $count)
                                
                                // Source indicator
                                if !addressHook.items.isEmpty {
                                    HStack {
                                        Image(systemName: "building.2")
                                            .foregroundStyle(.blue)
                                        Text("Address Database")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                PrimaryButton(
                                    title: addressHook.isLoading ? "Searching…" : 
                                           (!addressHook.items.isEmpty ? "Found \(addressHook.items.count) Homes" : "Find \(count.rawValue) Nearby"),
                                    enabled: selectedCenter != nil && !addressHook.isLoading,
                                    style: !addressHook.items.isEmpty ? .success : .primary
                                ) {
                                    Task {
                                        if let c = selectedCenter {
                                            addressHook.fetchNearest(center: c, target: count.rawValue)
                                        }
                                    }
                                }
                                
                                if let err = addressHook.error {
                                    Text(err)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        } else if source == .sameStreet {
                            // Same street interface - similar to closestHome
                            AddressSearchField(auto: auto) { suggestion in
                                selectedCenter = suggestion.coordinate
                                seedLabel = auto.query
                                auto.clear()   // ensure list is hidden after parent handles selection
                            }
                            
                            // Show current chosen seed (from text or map)
                            if !seedLabel.isEmpty {
                                Text(seedLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Count selection picker
                            FormRowMenuPicker("How many addresses?",
                                               options: AddressCountOption.allCases,
                                               selection: $count)
                            
                            // Source indicator
                            if !addressHook.items.isEmpty {
                                HStack {
                                    Image(systemName: "building.2")
                                        .foregroundStyle(.blue)
                                    Text("Address Database")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            PrimaryButton(
                                title: addressHook.isLoading ? "Searching…" : 
                                       (!addressHook.items.isEmpty ? "Found \(addressHook.items.count) Homes" : "Find \(count.rawValue) on Street"),
                                enabled: (!auto.query.isEmpty || selectedCenter != nil) && !addressHook.isLoading,
                                style: !addressHook.items.isEmpty ? .success : .primary
                            ) {
                                if let c = selectedCenter {
                                    addressHook.fetchSameStreet(seed: c, target: count.rawValue)
                                } else {
                                    // Forward geocode the query first
                                    Task {
                                        let geoAPI = GeoAPI.shared
                                        let seed = try await geoAPI.forwardGeocodeSeed(auto.query)
                                        addressHook.fetchSameStreet(seed: seed.coordinate, target: count.rawValue)
                                    }
                                }
                            }
                            
                            if let err = addressHook.error {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                .formContainerPadding()
                
                // Spacer to reveal CTA above tab bar
                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
            }
        }
        .navigationTitle("New Campaign")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let err = createHook.error { 
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote) 
                }
                PrimaryButton(title: "Create Campaign", enabled: canCreate) {
                    Task { await createCampaignTapped() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
        }
                .sheet(isPresented: $showMapSeed) {
                    MapDrawingView(initialCenter: selectedCenter, initialCount: count.rawValue) { coord, chosenCount, label in
                        self.selectedCenter = coord
                        self.count = AddressCountOption(rawValue: chosenCount) ?? .c100
                        self.seedLabel = label
                        self.auto.query = label
                        self.auto.selected = AddressSuggestion(id: UUID().uuidString, title: label, subtitle: nil, coordinate: coord)
                    }
                }
                .hidesTabBar()
    }
    
    private func createCampaignTapped() async {
        print("🚀 [CAMPAIGN DEBUG] Starting campaign creation workflow")
        print("🚀 [CAMPAIGN DEBUG] Campaign name: '\(name)'")
        print("🚀 [CAMPAIGN DEBUG] Campaign type: \(type.rawValue)")
        print("🚀 [CAMPAIGN DEBUG] Address source: \(source.rawValue)")
        print("🚀 [CAMPAIGN DEBUG] Can create: \(canCreate)")
        
        guard canCreate else { 
            print("❌ [CAMPAIGN DEBUG] Cannot create campaign - validation failed")
            return 
        }
        
        switch source {
        case .closestHome:
            print("🏠 [CAMPAIGN DEBUG] Creating campaign with closest home source")
            print("🏠 [CAMPAIGN DEBUG] Seed query: '\(seedQuery)'")
            print("🏠 [CAMPAIGN DEBUG] Target count: \(count.rawValue)")
            print("🏠 [CAMPAIGN DEBUG] Found \(addressHook.items.count) addresses")
            if let center = selectedCenter {
                print("🏠 [CAMPAIGN DEBUG] Seed center: (\(center.latitude), \(center.longitude))")
            } else {
                print("🏠 [CAMPAIGN DEBUG] Seed center: nil")
            }
            
            // Use new payload structure for closest home
            let addresses = addressHook.items.map { candidate in
                CampaignAddress(
                    address: candidate.address,
                    coordinate: candidate.coordinate
                )
            }
            print("🏠 [CAMPAIGN DEBUG] Addresses: \(addresses.count) records")
            
            let payload = CampaignCreatePayloadV2(
                name: name,
                description: description.isEmpty ? "Campaign created from \(source.displayName)" : description,
                type: type,
                addressSource: source,
                addressTargetCount: count.rawValue,
                seedQuery: seedQuery.isEmpty ? nil : seedQuery,
                seedLon: selectedCenter?.longitude,
                seedLat: selectedCenter?.latitude,
                addressesJSON: addresses
            )
            
            print("🏠 [CAMPAIGN DEBUG] Payload created, calling createV2...")
            if let created = await createHook.createV2(payload: payload, store: store) {
                print("✅ [CAMPAIGN DEBUG] Campaign created successfully with ID: \(created.id)")
                // Dismiss the sheet first, then navigate
                dismiss()
                // Small delay to ensure sheet is dismissed before navigation
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                await MainActor.run {
                    store.routeToV2Detail?(created.id)
                }
            } else {
                print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            }
            
        case .map:
            print("🗺️ [CAMPAIGN DEBUG] Creating campaign with map source")
            print("🗺️ [CAMPAIGN DEBUG] Seed label: '\(seedLabel)'")
            print("🗺️ [CAMPAIGN DEBUG] Target count: \(count.rawValue)")
            print("🗺️ [CAMPAIGN DEBUG] Found \(addressHook.items.count) addresses")
            if let center = selectedCenter {
                print("🗺️ [CAMPAIGN DEBUG] Seed center: (\(center.latitude), \(center.longitude))")
            } else {
                print("🗺️ [CAMPAIGN DEBUG] Seed center: nil")
            }
            
            // Use new payload structure for map
            let addresses = addressHook.items.map { candidate in
                CampaignAddress(
                    address: candidate.address,
                    coordinate: candidate.coordinate
                )
            }
            print("🗺️ [CAMPAIGN DEBUG] Addresses: \(addresses.count) records")
            
            let payload = CampaignCreatePayloadV2(
                name: name,
                description: description.isEmpty ? "Campaign created from \(source.displayName)" : description,
                type: type,
                addressSource: source,
                addressTargetCount: count.rawValue,
                seedQuery: seedLabel.isEmpty ? nil : seedLabel,
                seedLon: selectedCenter?.longitude,
                seedLat: selectedCenter?.latitude,
                addressesJSON: addresses
            )
            
            print("🗺️ [CAMPAIGN DEBUG] Payload created, calling createV2...")
            if let created = await createHook.createV2(payload: payload, store: store) {
                print("✅ [CAMPAIGN DEBUG] Campaign created successfully with ID: \(created.id)")
                // Dismiss the sheet first, then navigate
                dismiss()
                // Small delay to ensure sheet is dismissed before navigation
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                await MainActor.run {
                    store.routeToV2Detail?(created.id)
                }
            } else {
                print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            }
            
        case .sameStreet:
            print("🛣️ [CAMPAIGN DEBUG] Creating campaign with same street source")
            print("🛣️ [CAMPAIGN DEBUG] Seed label: '\(seedLabel)'")
            print("🛣️ [CAMPAIGN DEBUG] Target count: \(count.rawValue)")
            print("🛣️ [CAMPAIGN DEBUG] Found \(addressHook.items.count) addresses")
            if let center = selectedCenter {
                print("🛣️ [CAMPAIGN DEBUG] Seed center: (\(center.latitude), \(center.longitude))")
            } else {
                print("🛣️ [CAMPAIGN DEBUG] Seed center: nil")
            }
            
            // Use new payload structure for same street
            let addresses = addressHook.items.map { candidate in
                CampaignAddress(
                    address: candidate.address,
                    coordinate: candidate.coordinate
                )
            }
            print("🛣️ [CAMPAIGN DEBUG] Addresses: \(addresses.count) records")
            
            let payload = CampaignCreatePayloadV2(
                name: name,
                description: description.isEmpty ? "Campaign created from \(source.displayName)" : description,
                type: type,
                addressSource: source,
                addressTargetCount: count.rawValue,
                seedQuery: seedLabel.isEmpty ? nil : seedLabel,
                seedLon: selectedCenter?.longitude,
                seedLat: selectedCenter?.latitude,
                addressesJSON: addresses
            )
            
            print("🛣️ [CAMPAIGN DEBUG] Payload created, calling createV2...")
            if let created = await createHook.createV2(payload: payload, store: store) {
                print("✅ [CAMPAIGN DEBUG] Campaign created successfully with ID: \(created.id)")
                // Dismiss the sheet first, then navigate
                dismiss()
                // Small delay to ensure sheet is dismissed before navigation
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                await MainActor.run {
                    store.routeToV2Detail?(created.id)
                }
            } else {
                print("❌ [CAMPAIGN DEBUG] Campaign creation failed")
            }
            
        case .importList:
            print("📋 [CAMPAIGN DEBUG] Import list functionality not implemented")
            // TODO: Implement import list functionality if needed
        }
    }
}

#Preview {
    NavigationStack {
        NewCampaignScreen(store: CampaignV2Store.shared)
    }
}