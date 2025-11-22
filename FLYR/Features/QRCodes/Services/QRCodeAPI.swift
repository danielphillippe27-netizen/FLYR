import Foundation
import Supabase
import CoreLocation

/// API layer for all QR code backend operations
/// All Supabase queries live here - no queries in components or ViewModels
actor QRCodeAPI {
    static let shared = QRCodeAPI()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - QR Code Scans (Analytics)
    
    func fetchScansForAddress(addressId: UUID) async throws -> [QRCodeScan] {
        let response: [QRCodeScan] = try await client
            .from("qr_code_scans")
            .select()
            .eq("address_id", value: addressId)
            .order("scanned_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    func fetchScansForCampaign(campaignId: UUID) async throws -> [QRCodeScan] {
        // Use join to get scans for all addresses in campaign
        let response: [QRCodeScan] = try await client
            .from("qr_code_scans")
            .select("""
                id, address_id, scanned_at, device_info, user_agent, ip_address, referrer,
                campaign_addresses!inner(campaign_id)
            """)
            .eq("campaign_addresses.campaign_id", value: campaignId)
            .order("scanned_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    func getScanCountForAddress(addressId: UUID) async throws -> Int {
        let response = try await client
            .rpc("get_address_scan_count", params: ["p_address_id": addressId])
            .execute()
        
        if let data = try? JSONDecoder().decode(Int.self, from: response.data) {
            return data
        }
        return 0
    }
    
    func getScanCountForCampaign(campaignId: UUID) async throws -> Int {
        let response = try await client
            .rpc("get_campaign_scan_count", params: ["p_campaign_id": campaignId])
            .execute()
        
        if let data = try? JSONDecoder().decode(Int.self, from: response.data) {
            return data
        }
        return 0
    }
    
    func recordScan(addressId: UUID, deviceInfo: String? = nil, userAgent: String? = nil) async throws {
        let scanData: [String: AnyCodable] = [
            "address_id": AnyCodable(addressId),
            "device_info": AnyCodable(deviceInfo),
            "user_agent": AnyCodable(userAgent)
        ]
        
        _ = try await client
            .from("qr_code_scans")
            .insert(scanData)
            .execute()
    }
    
    // MARK: - Address Content (Landing Pages)
    
    struct AddressContentRow: Codable {
        let id: UUID
        let addressId: UUID
        let title: String
        let videos: [String]
        let images: [String]
        let forms: AnyCodable // JSONB - decode as flexible type
        let updatedAt: Date
        let createdAt: Date
        
        enum CodingKeys: String, CodingKey {
            case id
            case addressId = "address_id"
            case title
            case videos
            case images
            case forms
            case updatedAt = "updated_at"
            case createdAt = "created_at"
        }
    }
    
    func fetchAddressContent(addressId: UUID) async throws -> AddressContent? {
        let response: [AddressContentRow] = try await client
            .from("address_content")
            .select()
            .eq("address_id", value: addressId)
            .limit(1)
            .execute()
            .value
        
        guard let row = response.first else { return nil }
        
        // Convert forms JSONB to FormConfig array
        // Forms is stored as JSONB array, decode it properly
        let forms: [FormConfig] = try {
            // Try to decode forms as array of dictionaries
            guard let formsArray = row.forms.value as? [[String: Any]] else {
                return []
            }
            
            return try formsArray.map { formDict in
                let formId = formDict["id"] as? String ?? UUID().uuidString
                let fieldsArray = formDict["fields"] as? [[String: Any]] ?? []
                let fields = try fieldsArray.map { fieldDict in
                    FormField(
                        id: UUID(uuidString: fieldDict["id"] as? String ?? "") ?? UUID(),
                        label: fieldDict["label"] as? String ?? "",
                        type: FormField.FieldType(rawValue: fieldDict["type"] as? String ?? "text") ?? .text,
                        placeholder: fieldDict["placeholder"] as? String,
                        required: fieldDict["required"] as? Bool ?? false,
                        options: fieldDict["options"] as? [String]
                    )
                }
                return FormConfig(
                    id: UUID(uuidString: formId) ?? UUID(),
                    title: formDict["title"] as? String ?? "",
                    fields: fields,
                    submitURL: formDict["submit_url"] as? String
                )
            }
        }()
        
        return AddressContent(
            id: row.id,
            addressId: row.addressId,
            title: row.title,
            videos: row.videos,
            images: row.images,
            forms: forms,
            updatedAt: row.updatedAt,
            createdAt: row.createdAt
        )
    }
    
    func upsertAddressContent(_ content: AddressContent) async throws -> AddressContent {
        // Convert FormConfig array to JSONB
        let formsJSON: [[String: AnyCodable]] = content.forms.map { form in
            [
                "id": AnyCodable(form.id),
                "title": AnyCodable(form.title),
                "fields": AnyCodable(form.fields.map { field in
                    [
                        "id": AnyCodable(field.id),
                        "label": AnyCodable(field.label),
                        "type": AnyCodable(field.type.rawValue),
                        "placeholder": AnyCodable(field.placeholder),
                        "required": AnyCodable(field.required),
                        "options": AnyCodable(field.options)
                    ] as [String: AnyCodable]
                }),
                "submit_url": AnyCodable(form.submitURL)
            ] as [String: AnyCodable]
        }
        
        let contentData: [String: AnyCodable] = [
            "id": AnyCodable(content.id),
            "address_id": AnyCodable(content.addressId),
            "title": AnyCodable(content.title),
            "videos": AnyCodable(content.videos),
            "images": AnyCodable(content.images),
            "forms": AnyCodable(formsJSON)
        ]
        
        let response: [AddressContentRow] = try await client
            .from("address_content")
            .upsert(contentData, onConflict: "address_id")
            .select()
            .execute()
            .value
        
        guard let row = response.first else {
            throw NSError(domain: "QRCodeAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upsert address content"])
        }
        
        // Convert back to AddressContent model
        let forms: [FormConfig] = try {
            // Try to decode forms as array of dictionaries
            guard let formsArray = row.forms.value as? [[String: Any]] else {
                return []
            }
            
            return try formsArray.map { formDict in
                let formId = formDict["id"] as? String ?? UUID().uuidString
                let fieldsArray = formDict["fields"] as? [[String: Any]] ?? []
                let fields = try fieldsArray.map { fieldDict in
                    FormField(
                        id: UUID(uuidString: fieldDict["id"] as? String ?? "") ?? UUID(),
                        label: fieldDict["label"] as? String ?? "",
                        type: FormField.FieldType(rawValue: fieldDict["type"] as? String ?? "text") ?? .text,
                        placeholder: fieldDict["placeholder"] as? String,
                        required: fieldDict["required"] as? Bool ?? false,
                        options: fieldDict["options"] as? [String]
                    )
                }
                return FormConfig(
                    id: UUID(uuidString: formId) ?? UUID(),
                    title: formDict["title"] as? String ?? "",
                    fields: fields,
                    submitURL: formDict["submit_url"] as? String
                )
            }
        }()
        
        return AddressContent(
            id: row.id,
            addressId: row.addressId,
            title: row.title,
            videos: row.videos,
            images: row.images,
            forms: forms,
            updatedAt: row.updatedAt,
            createdAt: row.createdAt
        )
    }
    
    // MARK: - QR Codes by Campaign (Manage)
    
    func fetchQRCodesForCampaign(campaignId: UUID) async throws -> [QRCodeAddress] {
        let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
        
        return addresses.map { addressRow in
            let (webURL, deepLinkURL) = QRCodeAddress.generateURLs(for: addressRow.id)
            return QRCodeAddress(
                addressId: addressRow.id,
                formatted: addressRow.formatted,
                coordinate: CLLocationCoordinate2D(latitude: addressRow.lat, longitude: addressRow.lon),
                webURL: webURL,
                deepLinkURL: deepLinkURL
            )
        }
    }
    
    // MARK: - Campaigns (for selection)
    
    func fetchCampaigns() async throws -> [CampaignListItem] {
        let dbRows = try await CampaignsAPI.shared.fetchCampaignsMetadata()
        return dbRows.map { CampaignListItem(from: $0) }
    }
    
    func fetchAddressesForCampaign(campaignId: UUID) async throws -> [AddressRow] {
        let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
        return addresses.map { addressRow in
            AddressRow(
                id: addressRow.id,
                formatted: addressRow.formatted,
                coordinate: CLLocationCoordinate2D(latitude: addressRow.lat, longitude: addressRow.lon)
            )
        }
    }
    
    // MARK: - QR Sets
    
    /// Fetch all QR sets for the current user
    func fetchQRSets() async throws -> [QRSet] {
        // Get current user ID
        let session = try await client.auth.session
        let userId = session.user.id
        
        let response = try await client
            .from("qr_sets")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRSetDBRow] = try decoder.decode([QRSetDBRow].self, from: response.data)
        
        return dbRows.map { $0.toQRSet() }
    }
    
    /// Fetch QR codes for a specific set
    func fetchQRCodesForSet(setId: UUID) async throws -> [QRCode] {
        // First, get the QR set to retrieve qr_code_ids
        let setResponse = try await client
            .from("qr_sets")
            .select("qr_code_ids")
            .eq("id", value: setId.uuidString)
            .limit(1)
            .execute()
        
        struct QRSetIdsRow: Codable {
            let qrCodeIds: [UUID]
            
            enum CodingKeys: String, CodingKey {
                case qrCodeIds = "qr_code_ids"
            }
        }
        
        let decoder = createSupabaseDecoder()
        let setRows: [QRSetIdsRow] = try decoder.decode([QRSetIdsRow].self, from: setResponse.data)
        
        guard let setRow = setRows.first, !setRow.qrCodeIds.isEmpty else {
            return []
        }
        
        // Fetch QR codes using the IDs array
        let qrCodeIds = setRow.qrCodeIds.map { $0.uuidString }
        
        let response = try await client
            .from("qr_codes")
            .select()
            .in("id", values: qrCodeIds)
            .order("created_at", ascending: false)
            .execute()
        
        let qrCodeRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return qrCodeRows.map { $0.toQRCode() }
    }
    
    // MARK: - Helper
    
    /// Create a JSONDecoder with Supabase date handling
    private nonisolated func createSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let dt = iso.date(from: s) { return dt }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let dt = iso2.date(from: s) { return dt }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }
        return decoder
    }
}

