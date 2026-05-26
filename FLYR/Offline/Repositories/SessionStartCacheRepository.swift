import Foundation
import GRDB

private struct CachedSessionFarmRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_session_farms"

    let id: String
    let userId: String
    let workspaceId: String?
    let isActive: Int
    let createdAt: String?
    let payloadJSON: String
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }
}

private struct CachedRouteAssignmentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_route_assignments"

    let id: String
    let workspaceId: String
    let status: String?
    let updatedAt: String?
    let payloadJSON: String
    let cachedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case workspaceId = "workspace_id"
        case status
        case updatedAt = "updated_at"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case status
        case updatedAt = "updated_at"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }
}

private struct CachedRouteAssignmentDetailRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_route_assignment_details"

    let assignmentId: String
    let routePlanId: String
    let payloadJSON: String
    let cachedAt: String?

    enum Columns: String, ColumnExpression {
        case assignmentId = "assignment_id"
        case routePlanId = "route_plan_id"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case routePlanId = "route_plan_id"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }
}

private struct CachedRoutePlanDetailRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_route_plan_details"

    let routePlanId: String
    let payloadJSON: String
    let cachedAt: String?

    enum Columns: String, ColumnExpression {
        case routePlanId = "route_plan_id"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }

    enum CodingKeys: String, CodingKey {
        case routePlanId = "route_plan_id"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }
}

final class SessionStartCacheRepository {
    static let shared = SessionStartCacheRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func upsertFarms(_ farms: [Farm], userId: UUID, workspaceId: UUID?) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for farm in farms {
                guard let payloadJSON = OfflineJSONCodec.encode(farm) else { continue }
                let record = CachedSessionFarmRecord(
                    id: farm.id.uuidString,
                    userId: userId.uuidString,
                    workspaceId: farm.workspaceId?.uuidString ?? workspaceId?.uuidString,
                    isActive: farm.isActive ? 1 : 0,
                    createdAt: OfflineDateCodec.string(from: farm.createdAt),
                    payloadJSON: payloadJSON,
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func getCachedFarms(userId: UUID, workspaceId: UUID?) async -> [Farm] {
        (try? await dbQueue.read { db in
            var request = CachedSessionFarmRecord
                .filter(Column("user_id") == userId.uuidString)
            if let workspaceId {
                request = request.filter(Column("workspace_id") == workspaceId.uuidString || Column("workspace_id") == nil)
            }

            return try request
                .order(Column("created_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(Farm.self, from: $0.payloadJSON) }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        }) ?? []
    }

    func upsertRouteAssignments(_ assignments: [RouteAssignmentSummary], workspaceId: UUID) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for assignment in assignments {
                guard let payloadJSON = OfflineJSONCodec.encode(assignment) else { continue }
                let record = CachedRouteAssignmentRecord(
                    id: assignment.id.uuidString,
                    workspaceId: workspaceId.uuidString,
                    status: assignment.status,
                    updatedAt: assignment.updatedAt.map(OfflineDateCodec.string(from:)),
                    payloadJSON: payloadJSON,
                    cachedAt: cachedAt
                )
                try record.save(db)
            }
        }
    }

    func getCachedRouteAssignments(workspaceId: UUID) async -> [RouteAssignmentSummary] {
        (try? await dbQueue.read { db in
            try CachedRouteAssignmentRecord
                .filter(Column("workspace_id") == workspaceId.uuidString)
                .order(Column("updated_at").desc, Column("cached_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(RouteAssignmentSummary.self, from: $0.payloadJSON) }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.updatedAt ?? .distantPast
                    let rhsDate = rhs.updatedAt ?? .distantPast
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        }) ?? []
    }

    func upsertRouteAssignmentDetail(_ detail: RouteAssignmentDetailPayload) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        guard let payloadJSON = OfflineJSONCodec.encode(detail) else { return }
        let record = CachedRouteAssignmentDetailRecord(
            assignmentId: detail.assignmentId.uuidString,
            routePlanId: detail.routePlanId.uuidString,
            payloadJSON: payloadJSON,
            cachedAt: cachedAt
        )
        try? await dbQueue.write { db in
            try record.save(db)
        }
    }

    func getCachedRouteAssignmentDetail(assignmentId: UUID) async -> RouteAssignmentDetailPayload? {
        try? await dbQueue.read { db in
            guard let record = try CachedRouteAssignmentDetailRecord.fetchOne(db, key: assignmentId.uuidString) else {
                return nil
            }
            return OfflineJSONCodec.decode(RouteAssignmentDetailPayload.self, from: record.payloadJSON)
        }
    }

    func upsertRoutePlanDetail(_ detail: RoutePlanDetail) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        guard let payloadJSON = OfflineJSONCodec.encode(detail) else { return }
        let record = CachedRoutePlanDetailRecord(
            routePlanId: detail.id.uuidString,
            payloadJSON: payloadJSON,
            cachedAt: cachedAt
        )
        try? await dbQueue.write { db in
            try record.save(db)
        }
    }

    func getCachedRoutePlanDetail(routePlanId: UUID) async -> RoutePlanDetail? {
        try? await dbQueue.read { db in
            guard let record = try CachedRoutePlanDetailRecord.fetchOne(db, key: routePlanId.uuidString) else {
                return nil
            }
            return OfflineJSONCodec.decode(RoutePlanDetail.self, from: record.payloadJSON)
        }
    }
}
