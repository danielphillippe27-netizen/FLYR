import Foundation
import Combine

@MainActor
final class UseCreateCampaign: ObservableObject {
    @Published var isCreating = false
    @Published var error: String?
    
    func createV2(payload: CampaignCreatePayloadV2, store: CampaignV2Store) async -> CampaignV2? {
        print("🎣 [HOOK DEBUG] UseCreateCampaign.createV2 called")
        print("🎣 [HOOK DEBUG] Payload name: '\(payload.name)'")
        print("🎣 [HOOK DEBUG] Payload type: \(payload.type?.rawValue ?? "nil")")
        print("🎣 [HOOK DEBUG] Address count: \(payload.addressesJSON.count)")
        
        isCreating = true
        defer { 
            isCreating = false
            print("🎣 [HOOK DEBUG] UseCreateCampaign.createV2 completed")
        }
        
        do {
            print("🎣 [HOOK DEBUG] Calling CampaignsAPI.shared.createV2...")
            let created = try await CampaignsAPI.shared.createV2(payload)
            print("🎣 [HOOK DEBUG] API call successful, appending to store...")
            store.append(created)
            print("✅ [HOOK DEBUG] Campaign created and added to store successfully")
            return created
        } catch {
            print("❌ [HOOK DEBUG] Campaign creation failed: \(error)")
            self.error = "\(error)"
            return nil
        }
    }
    
    func create(draft: CampaignDraft, store: CampaignV2Store) async -> CampaignV2? {
        print("🎣 [HOOK DEBUG] UseCreateCampaign.create called (legacy)")
        print("🎣 [HOOK DEBUG] Draft name: '\(draft.name)'")
        print("🎣 [HOOK DEBUG] Draft type: \(draft.type.rawValue)")
        print("🎣 [HOOK DEBUG] Address count: \(draft.addresses.count)")
        
        isCreating = true
        defer { 
            isCreating = false
            print("🎣 [HOOK DEBUG] UseCreateCampaign.create completed")
        }
        
        do {
            print("🎣 [HOOK DEBUG] Calling CampaignsAPI.shared.createV2 with draft...")
            let created = try await CampaignsAPI.shared.createV2(draft)
            print("🎣 [HOOK DEBUG] API call successful, appending to store...")
            store.append(created)
            print("✅ [HOOK DEBUG] Legacy campaign created and added to store successfully")
            return created
        } catch {
            print("❌ [HOOK DEBUG] Legacy campaign creation failed: \(error)")
            self.error = "\(error)"
            return nil
        }
    }
}
