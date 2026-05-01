import Foundation
import GRDB

enum OfflineMigrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("phase1_offline_first_v1") { db in
            try db.create(table: "cached_campaigns", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text)
                t.column("mode", .text)
                t.column("boundary_geojson", .text)
                t.column("payload_json", .text)
                t.column("downloaded_at", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_buildings", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("source_id", .text)
                t.column("external_id", .text)
                t.column("geometry_geojson", .text).notNull()
                t.column("properties_json", .text)
                t.column("payload_json", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_addresses", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("building_id", .text)
                t.column("address", .text)
                t.column("unit", .text)
                t.column("city", .text)
                t.column("province", .text)
                t.column("postal_code", .text)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("payload_json", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_building_address_links", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("building_id", .text).notNull()
                t.column("address_id", .text).notNull()
                t.column("confidence", .double)
                t.column("source", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_address_statuses", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("address_id", .text)
                t.column("building_id", .text)
                t.column("status", .text)
                t.column("outcome", .text)
                t.column("notes", .text)
                t.column("payload_json", .text)
                t.column("updated_at", .text)
                t.column("dirty", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "cached_roads", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("geometry_geojson", .text).notNull()
                t.column("properties_json", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "local_sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("remote_id", .text)
                t.column("campaign_id", .text).notNull()
                t.column("mode", .text)
                t.column("started_at", .text)
                t.column("ended_at", .text)
                t.column("status", .text)
                t.column("distance_meters", .double).notNull().defaults(to: 0)
                t.column("path_geojson", .text)
                t.column("path_geojson_normalized", .text)
                t.column("payload_json", .text)
                t.column("created_offline", .integer).notNull().defaults(to: 0)
                t.column("updated_at", .text)
                t.column("synced_at", .text)
            }

            try db.create(table: "local_session_points", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("accuracy", .double)
                t.column("speed", .double)
                t.column("heading", .double)
                t.column("altitude", .double)
                t.column("timestamp", .text).notNull()
                t.column("accepted", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text)
            }

            try db.create(table: "local_session_events", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                t.column("campaign_id", .text).notNull()
                t.column("entity_type", .text)
                t.column("entity_id", .text)
                t.column("event_type", .text)
                t.column("payload_json", .text)
                t.column("occurred_at", .text)
                t.column("synced_at", .text)
            }

            try db.create(table: "sync_outbox", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("payload_json", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("attempted_at", .text)
                t.column("synced_at", .text)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("error_message", .text)
            }

            try db.create(table: "campaign_downloads", ifNotExists: true) { t in
                t.column("campaign_id", .text).primaryKey()
                t.column("status", .text)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("started_at", .text)
                t.column("completed_at", .text)
                t.column("error_message", .text)
                t.column("last_synced_at", .text)
            }

            try db.create(index: "idx_cached_buildings_campaign_id", on: "cached_buildings", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_addresses_campaign_id", on: "cached_addresses", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_links_campaign_id", on: "cached_building_address_links", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_statuses_campaign_id", on: "cached_address_statuses", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_statuses_campaign_address", on: "cached_address_statuses", columns: ["campaign_id", "address_id"], ifNotExists: true)
            try db.create(index: "idx_cached_roads_campaign_id", on: "cached_roads", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_local_session_points_session_id", on: "local_session_points", columns: ["session_id"], ifNotExists: true)
            try db.create(index: "idx_local_session_events_session_id", on: "local_session_events", columns: ["session_id"], ifNotExists: true)
            try db.create(index: "idx_sync_outbox_created_at", on: "sync_outbox", columns: ["created_at"], ifNotExists: true)
            try db.create(index: "idx_sync_outbox_synced_at", on: "sync_outbox", columns: ["synced_at", "created_at"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_offline_contacts_v1") { db in
            try db.create(table: "cached_contacts", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text)
                t.column("workspace_id", .text)
                t.column("full_name", .text).notNull()
                t.column("phone", .text)
                t.column("email", .text)
                t.column("address", .text).notNull()
                t.column("campaign_id", .text)
                t.column("farm_id", .text)
                t.column("gers_id", .text)
                t.column("address_id", .text)
                t.column("tags", .text)
                t.column("status", .text).notNull()
                t.column("last_contacted", .text)
                t.column("notes", .text)
                t.column("reminder_date", .text)
                t.column("payload_json", .text)
                t.column("updated_at", .text)
                t.column("dirty", .integer).notNull().defaults(to: 0)
                t.column("synced_at", .text)
            }

            try db.create(table: "cached_contact_activities", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("contact_id", .text).notNull()
                t.column("type", .text).notNull()
                t.column("note", .text)
                t.column("timestamp", .text).notNull()
                t.column("created_at", .text)
                t.column("payload_json", .text)
                t.column("dirty", .integer).notNull().defaults(to: 0)
                t.column("synced_at", .text)
            }

            try db.create(index: "idx_cached_contacts_user_id", on: "cached_contacts", columns: ["user_id"], ifNotExists: true)
            try db.create(index: "idx_cached_contacts_workspace_id", on: "cached_contacts", columns: ["workspace_id"], ifNotExists: true)
            try db.create(index: "idx_cached_contacts_campaign_id", on: "cached_contacts", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_contacts_address_id", on: "cached_contacts", columns: ["address_id"], ifNotExists: true)
            try db.create(index: "idx_cached_contact_activities_contact_id", on: "cached_contact_activities", columns: ["contact_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_offline_address_metadata_v1") { db in
            try db.create(table: "cached_address_capture_metadata", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("address_id", .text).notNull()
                t.column("contact_name", .text)
                t.column("lead_status", .text)
                t.column("product_interest", .text)
                t.column("follow_up_date", .text)
                t.column("raw_transcript", .text)
                t.column("ai_summary", .text)
                t.column("updated_at", .text)
                t.column("dirty", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "idx_cached_address_capture_campaign_address", on: "cached_address_capture_metadata", columns: ["campaign_id", "address_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_outbox_durability_v2") { db in
            try db.alter(table: "sync_outbox") { t in
                t.add(column: "client_mutation_id", .text)
                t.add(column: "operation_version", .integer).notNull().defaults(to: 1)
                t.add(column: "status", .text).notNull().defaults(to: "pending")
                t.add(column: "retry_after", .text)
                t.add(column: "dead_lettered_at", .text)
            }

            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET client_mutation_id = id,
                    status = COALESCE(status, 'pending'),
                    operation_version = COALESCE(operation_version, 1)
                WHERE client_mutation_id IS NULL
                   OR status IS NULL
                   OR operation_version IS NULL
                """
            )

            try db.create(index: "idx_sync_outbox_status_retry", on: "sync_outbox", columns: ["status", "retry_after", "created_at"], ifNotExists: true)
            try db.create(index: "idx_sync_outbox_client_mutation", on: "sync_outbox", columns: ["client_mutation_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_outbox_dependency_keys_v3") { db in
            let columns = try db.columns(in: "sync_outbox").map(\.name)
            if !columns.contains("dependency_key") {
                try db.alter(table: "sync_outbox") { t in
                    t.add(column: "dependency_key", .text)
                }
            }

            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET dependency_key = entity_type || ':' || entity_id
                WHERE dependency_key IS NULL
                """
            )

            try db.create(index: "idx_sync_outbox_dependency", on: "sync_outbox", columns: ["dependency_key", "created_at"], ifNotExists: true)
        }

        return migrator
    }
}
