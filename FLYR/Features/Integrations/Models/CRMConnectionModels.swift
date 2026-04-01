import Foundation

// MARK: - CRM Connection (matches crm_connections table)

struct CRMConnection: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let provider: String
    let status: String
    let connectedAt: Date?
    let lastSyncAt: Date?
    let updatedAt: Date?
    let metadata: CRMConnectionMetadata?
    let errorReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case provider
        case status
        case connectedAt = "connected_at"
        case lastSyncAt = "last_sync_at"
        case updatedAt = "updated_at"
        case metadata
        case errorReason = "error_reason"
    }

    var isConnected: Bool { status == "connected" }
}

struct CRMConnectionMetadata: Codable, Equatable {
    let name: String?
    let company: String?
    let providerLabel: String?
    let accountName: String?
    let userEmail: String?
    let tokenHint: String?
    let lastValidatedAt: String?
    let lastTestedAt: String?
    let lastTestResult: String?
}

// MARK: - FUB Connect API (body: api_key only; backend uses JWT for user_id)

struct FUBConnectRequest: Encodable {
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}

struct FUBConnectResponse: Decodable {
    let connected: Bool
    let account: FUBAccount?
    let error: String?

    struct FUBAccount: Decodable {
        let name: String?
        let company: String?
    }
}

struct CRMDisconnectResponse: Decodable {
    let disconnected: Bool?
    let success: Bool?
    let message: String?
    let error: String?
}

// MARK: - Push Lead (POST /api/integrations/fub/push-lead)

struct FUBPushLeadRequest: Encodable {
    struct TaskPayload: Encodable {
        let title: String
        let dueDate: String

        enum CodingKeys: String, CodingKey {
            case title
            case dueDate = "due_date"
        }
    }

    struct AppointmentPayload: Encodable {
        let date: String
        let title: String?
        let notes: String?
    }

    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let message: String?
    let source: String?
    let sourceUrl: String?
    let campaignId: String?
    let metadata: [String: String]?
    let task: TaskPayload?
    let appointment: AppointmentPayload?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, email, phone, address, city, state, zip
        case message, source, sourceUrl, campaignId, metadata
        case task, appointment
    }
}

struct FUBPushLeadResponse: Decodable {
    let success: Bool
    let message: String?
    let fubEventId: String?
    let fubPersonId: Int?
    let fubNoteId: Int?
    let fubTaskId: Int?
    let fubAppointmentId: Int?
    let noteCreated: Bool?
    let taskCreated: Bool?
    let appointmentCreated: Bool?
    let followUpErrors: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, fubEventId, fubPersonId, fubNoteId, fubTaskId, fubAppointmentId
        case noteCreated, taskCreated, appointmentCreated, followUpErrors, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        fubEventId = Self.decodeStringOrInt(c, forKey: .fubEventId)
        fubPersonId = Self.decodeIntFlexible(c, forKey: .fubPersonId)
        fubNoteId = Self.decodeIntFlexible(c, forKey: .fubNoteId)
        fubTaskId = Self.decodeIntFlexible(c, forKey: .fubTaskId)
        fubAppointmentId = Self.decodeIntFlexible(c, forKey: .fubAppointmentId)
        noteCreated = try c.decodeIfPresent(Bool.self, forKey: .noteCreated)
        taskCreated = try c.decodeIfPresent(Bool.self, forKey: .taskCreated)
        appointmentCreated = try c.decodeIfPresent(Bool.self, forKey: .appointmentCreated)
        followUpErrors = try c.decodeIfPresent([String].self, forKey: .followUpErrors)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    private static func decodeStringOrInt(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        return nil
    }

    private static func decodeIntFlexible(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
        return nil
    }
}

// MARK: - Sync CRM (POST /api/leads/sync-crm)

struct FUBSyncCRMResponse: Decodable {
    let success: Bool
    let message: String?
    let synced: Int?
    let error: String?
}

// MARK: - Status (GET /api/integrations/fub/status)

struct FUBStatusResponse: Decodable {
    let connected: Bool
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let lastSyncAt: String?
    let lastError: String?
    let error: String?
}

// MARK: - Test (POST /api/integrations/fub/test, test-push)

struct FUBTestResponse: Decodable {
    let success: Bool
    let message: String?
    let fubPersonId: Int?
    let fubNoteId: Int?
    let fubTaskId: Int?
    let fubAppointmentId: Int?
    let noteCreated: Bool?
    let taskCreated: Bool?
    let appointmentCreated: Bool?
    let followUpErrors: [String]?
    let error: String?
}

// MARK: - BoldTrail / kvCORE

struct BoldTrailConnectRequest: Encodable {
    let apiToken: String

    enum CodingKeys: String, CodingKey {
        case apiToken = "api_token"
    }
}

struct BoldTrailConnectResponse: Decodable {
    struct Account: Decodable {
        let name: String?
        let email: String?
    }

    let connected: Bool?
    let disconnected: Bool?
    let success: Bool?
    let message: String?
    let error: String?
    let account: Account?
    let tokenHint: String?
}

struct BoldTrailStatusResponse: Decodable {
    let connected: Bool
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let lastSyncAt: String?
    let lastError: String?
    let metadata: CRMConnectionMetadata?
    let error: String?
}

struct BoldTrailPushLeadRequest: Encodable {
    let id: String
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let source: String
    let campaignId: String?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case email
        case address
        case source
        case campaignId = "campaign_id"
        case notes
        case createdAt = "created_at"
    }
}

struct BoldTrailPushLeadResponse: Decodable {
    let success: Bool
    let message: String?
    let remoteContactId: String?
    let action: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case message
        case remoteContactId
        case remoteContactIdSnake = "remote_contact_id"
        case contactId
        case contactIdSnake = "contact_id"
        case id
        case action
        case error
        case detail
        case details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = Self.decodeBoolFlexible(c, forKey: .success) ?? false
        message = Self.decodeStringFlexible(c, forKeys: [.message, .detail, .details])
        remoteContactId = Self.decodeStringFlexible(
            c,
            forKeys: [.remoteContactId, .remoteContactIdSnake, .contactId, .contactIdSnake, .id]
        )
        action = Self.decodeStringFlexible(c, forKeys: [.action])
        error = Self.decodeStringFlexible(c, forKeys: [.error, .detail, .details])
    }

    private static func decodeBoolFlexible(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool? {
        if let value = try? c.decode(Bool.self, forKey: key) { return value }
        if let value = try? c.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? c.decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func decodeStringFlexible(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKeys keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? c.decode(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = try? c.decode(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? c.decode(Double.self, forKey: key) {
                let rounded = Double(Int(value))
                return rounded == value ? String(Int(value)) : String(value)
            }
        }
        return nil
    }
}

// MARK: - HubSpot (backend routes)

struct HubSpotOAuthStartResponse: Decodable {
    let success: Bool?
    let authorizeURL: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case authorizeURL = "authorizeUrl"
        case error
    }
}

struct HubSpotStatusResponse: Decodable {
    let connected: Bool
    let status: String?
    let updatedAt: String?
    let accountId: String?
    let accountName: String?
    let error: String?
}

struct HubSpotTestResponse: Decodable {
    let success: Bool?
    let message: String?
    let error: String?
}

struct HubSpotPushLeadRequest: Encodable {
    struct TaskPayload: Encodable {
        let title: String
        let dueDate: String

        enum CodingKeys: String, CodingKey {
            case title
            case dueDate = "due_date"
        }
    }

    struct AppointmentPayload: Encodable {
        let date: String
        let title: String?
        let notes: String?
    }

    let id: String
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let source: String
    let campaignId: String?
    let notes: String?
    let createdAt: String
    let task: TaskPayload?
    let appointment: AppointmentPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case email
        case address
        case source
        case campaignId = "campaign_id"
        case notes
        case createdAt = "created_at"
        case task
        case appointment
    }
}

struct HubSpotPushLeadResponse: Decodable {
    let success: Bool
    let message: String?
    let hubspotContactId: String?
    let noteCreated: Bool?
    let taskCreated: Bool?
    let meetingCreated: Bool?
    let partialErrors: [String]?
    let error: String?
}

// MARK: - Monday.com Integration

struct MondayBoardSummary: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let workspaceId: String?
    let workspaceName: String?
    let state: String?
    let columns: [MondayBoardColumn]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workspaceId
        case workspaceName
        case state
        case columns
    }

    init(
        id: String,
        name: String,
        workspaceId: String?,
        workspaceName: String?,
        state: String?,
        columns: [MondayBoardColumn] = []
    ) {
        self.id = id
        self.name = name
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.state = state
        self.columns = columns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeFlexibleString(container, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workspaceId = try Self.decodeFlexibleStringIfPresent(container, forKey: .workspaceId)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        columns = try container.decodeIfPresent([MondayBoardColumn].self, forKey: .columns) ?? []
    }

    private static func decodeFlexibleString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: container.codingPath + [key],
                debugDescription: "Expected string or int value."
            )
        )
    }

    private static func decodeFlexibleStringIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct MondayBoardColumn: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let type: String
}

struct MondayBoardsResponse: Decodable {
    let boards: [MondayBoardSummary]
    let selectedBoardId: String?
    let selectedBoardName: String?
    let accountId: String?
    let accountName: String?

    enum CodingKeys: String, CodingKey {
        case boards
        case selectedBoardId
        case selectedBoardName
        case accountId
        case accountName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boards = try container.decodeIfPresent([MondayBoardSummary].self, forKey: .boards) ?? []
        selectedBoardId = normalizedMondayBoardId(Self.decodeFlexibleStringIfPresent(container, forKey: .selectedBoardId))
        selectedBoardName = selectedBoardId == nil
            ? nil
            : normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .selectedBoardName))
        accountId = Self.decodeFlexibleStringIfPresent(container, forKey: .accountId)
        accountName = normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .accountName))
    }

    private static func decodeFlexibleStringIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct MondayBoardSelectionResponse: Decodable {
    let success: Bool
    let selectedBoardId: String?
    let selectedBoardName: String?

    enum CodingKeys: String, CodingKey {
        case success
        case selectedBoardId
        case selectedBoardName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        selectedBoardId = normalizedMondayBoardId(Self.decodeFlexibleStringIfPresent(container, forKey: .selectedBoardId))
        selectedBoardName = selectedBoardId == nil
            ? nil
            : normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .selectedBoardName))
    }

    private static func decodeFlexibleStringIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct MondayStatusResponse: Decodable {
    let connected: Bool?
    let isConnected: Bool?
    let selectedBoardId: String?
    let selectedBoardName: String?
    let accountId: String?
    let accountName: String?
    let workspaceId: String?
    let workspaceName: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case isConnected
        case selectedBoardId
        case selectedBoardName
        case accountId
        case accountName
        case workspaceId
        case workspaceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connected = Self.decodeFlexibleBoolIfPresent(container, forKey: .connected)
        isConnected = Self.decodeFlexibleBoolIfPresent(container, forKey: .isConnected)
        selectedBoardId = normalizedMondayBoardId(Self.decodeFlexibleStringIfPresent(container, forKey: .selectedBoardId))
        selectedBoardName = selectedBoardId == nil
            ? nil
            : normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .selectedBoardName))
        accountId = Self.decodeFlexibleStringIfPresent(container, forKey: .accountId)
        accountName = normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .accountName))
        workspaceId = Self.decodeFlexibleStringIfPresent(container, forKey: .workspaceId)
        workspaceName = normalizedDisplayString(try container.decodeIfPresent(String.self, forKey: .workspaceName))
    }

    var hasValidSelectedBoard: Bool {
        normalizedMondayBoardId(selectedBoardId) != nil
    }

    var resolvedIsConnected: Bool? {
        connected ?? isConnected
    }

    private static func decodeFlexibleStringIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func decodeFlexibleBoolIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

extension MondayBoardsResponse {
    var validBoards: [MondayBoardSummary] {
        boards.filter { normalizedMondayBoardId($0.id) != nil }
    }
}
