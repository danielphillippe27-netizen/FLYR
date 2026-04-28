import Foundation
import CoreLocation

enum SharedLiveCanvassingPresenceStatus: String, Codable, CaseIterable {
    case active
    case paused
    case inactive
}

enum SharedLiveCanvassingFreshness: Equatable {
    case live
    case stale
    case expired
}

struct SharedLiveCanvassingStalenessConfig: Equatable {
    let fadeAfter: TimeInterval
    let expireAfter: TimeInterval

    static let v1 = SharedLiveCanvassingStalenessConfig(
        fadeAfter: 60,
        expireAfter: 180
    )
}

struct CampaignPresenceRow: Codable, Equatable, Identifiable {
    let campaignId: UUID
    let userId: UUID
    let sessionId: UUID?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: Date
    let status: SharedLiveCanvassingPresenceStatus

    var id: String {
        "\(campaignId.uuidString.lowercased())-\(userId.uuidString.lowercased())"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        guard CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case userId = "user_id"
        case sessionId = "session_id"
        case latitude = "lat"
        case longitude = "lng"
        case updatedAt = "updated_at"
        case status
    }
}

struct CampaignMemberDirectoryRow: Decodable, Equatable, Identifiable {
    let userId: UUID
    let role: String
    let displayName: String
    let email: String?
    let avatarURL: String?
    let createdAt: Date

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
        case displayName = "display_name"
        case email
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

struct SharedCanvassingMember: Identifiable, Equatable {
    let userId: UUID
    let role: String
    let displayName: String
    let email: String?
    let avatarURL: String?
    let createdAt: Date

    var id: UUID { userId }

    var initials: String {
        Self.initials(from: displayName)
    }

    init(
        userId: UUID,
        role: String,
        displayName: String,
        email: String?,
        avatarURL: String?,
        createdAt: Date
    ) {
        self.userId = userId
        self.role = role
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.createdAt = createdAt
    }

    init(row: CampaignMemberDirectoryRow) {
        self.init(
            userId: row.userId,
            role: row.role,
            displayName: row.displayName,
            email: row.email,
            avatarURL: row.avatarURL,
            createdAt: row.createdAt
        )
    }

    private static func initials(from displayName: String) -> String {
        let parts = displayName
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

struct SharedCanvassingTeammate: Identifiable, Equatable {
    let userId: UUID
    let campaignId: UUID
    let sessionId: UUID?
    let displayName: String
    let initials: String
    let avatarURL: String?
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
    let presenceStatus: SharedLiveCanvassingPresenceStatus
    let freshness: SharedLiveCanvassingFreshness
    let opacity: Double

    var id: UUID { userId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isStale: Bool {
        freshness == .stale
    }

    var isPaused: Bool {
        presenceStatus == .paused
    }
}

enum SharedLiveCanvassingStartOutcome: Equatable {
    case joined
    case continueSolo(reason: String)
}

enum SharedLiveCanvassingAvailability: Equatable {
    case unknown
    case available
    case unavailable
}

enum SharedLiveCanvassingReducer {
    static func freshness(
        for updatedAt: Date,
        now: Date,
        config: SharedLiveCanvassingStalenessConfig = .v1
    ) -> SharedLiveCanvassingFreshness {
        let age = max(0, now.timeIntervalSince(updatedAt))
        if age >= config.expireAfter { return .expired }
        if age >= config.fadeAfter { return .stale }
        return .live
    }

    static func mergePresence(
        _ incoming: CampaignPresenceRow,
        into existing: [UUID: CampaignPresenceRow]
    ) -> [UUID: CampaignPresenceRow] {
        if let current = existing[incoming.userId], current.updatedAt > incoming.updatedAt {
            return existing
        }

        var merged = existing
        if incoming.status == .inactive {
            merged.removeValue(forKey: incoming.userId)
        } else {
            merged[incoming.userId] = incoming
        }
        return merged
    }

    static func mergeHomeState(
        _ incoming: AddressStatusRow,
        into existing: [UUID: AddressStatusRow]
    ) -> [UUID: AddressStatusRow] {
        if let current = existing[incoming.addressId], current.updatedAt > incoming.updatedAt {
            return existing
        }

        var merged = existing
        merged[incoming.addressId] = incoming
        return merged
    }

    static func teammates(
        from presenceRows: [UUID: CampaignPresenceRow],
        directory: [UUID: SharedCanvassingMember],
        currentUserId: UUID?,
        currentSessionId: UUID?,
        now: Date,
        config: SharedLiveCanvassingStalenessConfig = .v1
    ) -> [SharedCanvassingTeammate] {
        presenceRows.values.compactMap { row in
            guard row.userId != currentUserId else { return nil }
            guard row.status != .inactive else { return nil }
            guard currentSessionId == nil || row.sessionId == currentSessionId else { return nil }
            guard let coordinate = row.coordinate else { return nil }

            let freshness = freshness(for: row.updatedAt, now: now, config: config)
            guard freshness != .expired else { return nil }

            let member = directory[row.userId] ?? SharedCanvassingMember(
                userId: row.userId,
                role: "member",
                displayName: "Rep \(row.userId.uuidString.prefix(4))",
                email: nil,
                avatarURL: nil,
                createdAt: row.updatedAt
            )

            return SharedCanvassingTeammate(
                userId: row.userId,
                campaignId: row.campaignId,
                sessionId: row.sessionId,
                displayName: member.displayName,
                initials: member.initials,
                avatarURL: member.avatarURL,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                updatedAt: row.updatedAt,
                presenceStatus: row.status,
                freshness: freshness,
                opacity: opacity(for: freshness, status: row.status)
            )
        }
        .sorted {
            if $0.freshness != $1.freshness {
                return freshnessSortKey($0.freshness) < freshnessSortKey($1.freshness)
            }
            if $0.presenceStatus != $1.presenceStatus {
                return statusSortKey($0.presenceStatus) < statusSortKey($1.presenceStatus)
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func nonFatalJoinOutcome(for error: Error) -> SharedLiveCanvassingStartOutcome {
        .continueSolo(reason: error.localizedDescription)
    }

    private static func opacity(
        for freshness: SharedLiveCanvassingFreshness,
        status: SharedLiveCanvassingPresenceStatus
    ) -> Double {
        switch (freshness, status) {
        case (.live, .active):
            return 1
        case (.live, .paused):
            return 0.72
        case (.stale, .active):
            return 0.46
        case (.stale, .paused):
            return 0.34
        case (.expired, _), (_, .inactive):
            return 0
        }
    }

    private static func freshnessSortKey(_ freshness: SharedLiveCanvassingFreshness) -> Int {
        switch freshness {
        case .live:
            return 0
        case .stale:
            return 1
        case .expired:
            return 2
        }
    }

    private static func statusSortKey(_ status: SharedLiveCanvassingPresenceStatus) -> Int {
        switch status {
        case .active:
            return 0
        case .paused:
            return 1
        case .inactive:
            return 2
        }
    }
}
