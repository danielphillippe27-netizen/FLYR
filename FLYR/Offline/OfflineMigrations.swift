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

            try db.create(table: "local_fallback_buildings", ifNotExists: true) { t in
                t.column("local_geometry_id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("address_id", .text).notNull()
                t.column("geometry_geojson", .text).notNull()
                t.column("geometry_source", .text).notNull().defaults(to: "manual_fallback")
                t.column("payload_json", .text)
                t.column("created_at", .text)
                t.column("updated_at", .text)
                t.column("sync_status", .text).notNull().defaults(to: "pending")
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
            try db.create(index: "idx_cached_links_campaign_address_unique", on: "cached_building_address_links", columns: ["campaign_id", "address_id"], unique: true, ifNotExists: true)
            try db.create(index: "idx_local_fallback_buildings_campaign_id", on: "local_fallback_buildings", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_local_fallback_buildings_campaign_address", on: "local_fallback_buildings", columns: ["campaign_id", "address_id"], ifNotExists: true)
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

        migrator.registerMigration("calendar_events_v1") { db in
            try db.create(table: "cached_calendar_events", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text)
                t.column("workspace_id", .text)
                t.column("title", .text).notNull()
                t.column("start_at", .text).notNull()
                t.column("end_at", .text).notNull()
                t.column("is_all_day", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("location", .text)
                t.column("color_key", .text).notNull().defaults(to: "red")
                t.column("payload_json", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.column("deleted_at", .text)
                t.column("dirty", .integer).notNull().defaults(to: 0)
                t.column("synced_at", .text)
            }

            try db.create(index: "idx_cached_calendar_events_user_range", on: "cached_calendar_events", columns: ["user_id", "start_at", "end_at"], ifNotExists: true)
            try db.create(index: "idx_cached_calendar_events_workspace_range", on: "cached_calendar_events", columns: ["workspace_id", "start_at", "end_at"], ifNotExists: true)
            try db.create(index: "idx_cached_calendar_events_dirty", on: "cached_calendar_events", columns: ["dirty", "updated_at"], ifNotExists: true)
        }

        migrator.registerMigration("calendar_events_type_contact_v2") { db in
            let existingColumns = Set(try db.columns(in: "cached_calendar_events").map(\.name))

            if !existingColumns.contains("event_type") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "event_type", .text).notNull().defaults(to: "appointment")
                }
            }
            if !existingColumns.contains("contact_id") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "contact_id", .text)
                }
            }
            if !existingColumns.contains("contact_name") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "contact_name", .text)
                }
            }
            if !existingColumns.contains("contact_address") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "contact_address", .text)
                }
            }
            try db.create(index: "idx_cached_calendar_events_contact_id", on: "cached_calendar_events", columns: ["contact_id"], ifNotExists: true)
        }

        migrator.registerMigration("calendar_events_source_link_v3") { db in
            let existingColumns = Set(try db.columns(in: "cached_calendar_events").map(\.name))

            if !existingColumns.contains("source_kind") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "source_kind", .text)
                }
            }
            if !existingColumns.contains("source_id") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "source_id", .text)
                }
            }
            try db.create(index: "idx_cached_calendar_events_source", on: "cached_calendar_events", columns: ["source_kind", "source_id", "event_type"], ifNotExists: true)
        }

        migrator.registerMigration("calendar_events_campaign_recurrence_v4") { db in
            let existingColumns = Set(try db.columns(in: "cached_calendar_events").map(\.name))

            if !existingColumns.contains("campaign_id") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "campaign_id", .text)
                }
            }
            if !existingColumns.contains("campaign_name") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "campaign_name", .text)
                }
            }
            if !existingColumns.contains("recurrence_rule") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "recurrence_rule", .text).notNull().defaults(to: "none")
                }
            }
            if !existingColumns.contains("recurrence_until") {
                try db.alter(table: "cached_calendar_events") { t in
                    t.add(column: "recurrence_until", .text)
                }
            }
            try db.create(index: "idx_cached_calendar_events_campaign_id", on: "cached_calendar_events", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_calendar_events_recurrence", on: "cached_calendar_events", columns: ["recurrence_rule", "recurrence_until"], ifNotExists: true)
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

        migrator.registerMigration("phase1_session_start_cache_v1") { db in
            try db.create(table: "cached_session_farms", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("workspace_id", .text)
                t.column("is_active", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text)
                t.column("payload_json", .text).notNull()
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_route_assignments", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("workspace_id", .text).notNull()
                t.column("status", .text)
                t.column("updated_at", .text)
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(table: "cached_route_assignment_details", ifNotExists: true) { t in
                t.column("assignment_id", .text).primaryKey()
                t.column("route_plan_id", .text).notNull()
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(table: "cached_route_plan_details", ifNotExists: true) { t in
                t.column("route_plan_id", .text).primaryKey()
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(index: "idx_cached_session_farms_user", on: "cached_session_farms", columns: ["user_id", "workspace_id"], ifNotExists: true)
            try db.create(index: "idx_cached_route_assignments_workspace", on: "cached_route_assignments", columns: ["workspace_id", "updated_at"], ifNotExists: true)
            try db.create(index: "idx_cached_route_assignment_details_plan", on: "cached_route_assignment_details", columns: ["route_plan_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_offline_farms_v1") { db in
            try db.create(table: "cached_farms", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("user_id", .text).notNull()
                t.column("workspace_id", .text)
                t.column("is_active", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text)
                t.column("updated_at", .text)
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(table: "cached_farm_touches", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("farm_id", .text).notNull()
                t.column("campaign_id", .text)
                t.column("cycle_number", .integer)
                t.column("date", .text)
                t.column("order_index", .integer)
                t.column("completed", .integer).notNull().defaults(to: 0)
                t.column("dirty", .integer).notNull().defaults(to: 0)
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
                t.column("synced_at", .text)
            }

            try db.create(table: "cached_farm_leads", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("farm_id", .text).notNull()
                t.column("touch_id", .text)
                t.column("created_at", .text)
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(table: "cached_farm_addresses", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("farm_id", .text).notNull()
                t.column("campaign_id", .text)
                t.column("campaign_address_id", .text)
                t.column("street_name", .text)
                t.column("house_number", .text)
                t.column("created_at", .text)
                t.column("payload_json", .text).notNull()
                t.column("cached_at", .text)
            }

            try db.create(table: "cached_farm_touch_address_statuses", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("farm_id", .text).notNull()
                t.column("farm_touch_id", .text)
                t.column("cycle_number", .integer)
                t.column("address_id", .text).notNull()
                t.column("status", .text).notNull()
                t.column("notes", .text)
                t.column("occurred_at", .text).notNull()
                t.column("dirty", .integer).notNull().defaults(to: 0)
                t.column("payload_json", .text)
                t.column("cached_at", .text)
                t.column("synced_at", .text)
            }

            try db.create(index: "idx_cached_farms_user_workspace", on: "cached_farms", columns: ["user_id", "workspace_id"], ifNotExists: true)
            try db.create(index: "idx_cached_farm_touches_farm", on: "cached_farm_touches", columns: ["farm_id", "date", "order_index"], ifNotExists: true)
            try db.create(index: "idx_cached_farm_leads_farm", on: "cached_farm_leads", columns: ["farm_id", "created_at"], ifNotExists: true)
            try db.create(index: "idx_cached_farm_addresses_farm", on: "cached_farm_addresses", columns: ["farm_id", "street_name", "house_number"], ifNotExists: true)
            try db.create(index: "idx_cached_farm_statuses_cycle", on: "cached_farm_touch_address_statuses", columns: ["farm_id", "cycle_number", "address_id", "occurred_at"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_offline_farm_leads_dirty_v2") { db in
            let columns = try db.columns(in: "cached_farm_leads").map(\.name)
            if !columns.contains("dirty") {
                try db.alter(table: "cached_farm_leads") { t in
                    t.add(column: "dirty", .integer).notNull().defaults(to: 0)
                }
            }
            if !columns.contains("synced_at") {
                try db.alter(table: "cached_farm_leads") { t in
                    t.add(column: "synced_at", .text)
                }
            }

            try db.create(index: "idx_cached_farm_leads_dirty", on: "cached_farm_leads", columns: ["dirty", "synced_at"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_local_fallback_buildings_v1") { db in
            try db.create(table: "local_fallback_buildings", ifNotExists: true) { t in
                t.column("local_geometry_id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("address_id", .text).notNull()
                t.column("geometry_geojson", .text).notNull()
                t.column("geometry_source", .text).notNull().defaults(to: "manual_fallback")
                t.column("payload_json", .text)
                t.column("created_at", .text)
                t.column("updated_at", .text)
                t.column("sync_status", .text).notNull().defaults(to: "pending")
            }

            try db.create(index: "idx_local_fallback_buildings_campaign_id", on: "local_fallback_buildings", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_local_fallback_buildings_campaign_address", on: "local_fallback_buildings", columns: ["campaign_id", "address_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_offline_address_orphans_v1") { db in
            try db.create(table: "cached_address_orphans", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("address_id", .text).notNull()
                t.column("nearest_building_id", .text)
                t.column("nearest_distance", .double)
                t.column("status", .text)
                t.column("suggested_street", .text)
                t.column("address_street", .text)
                t.column("coordinate_json", .text)
                t.column("updated_at", .text)
            }

            try db.create(index: "idx_cached_orphans_campaign", on: "cached_address_orphans", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_orphans_campaign_building", on: "cached_address_orphans", columns: ["campaign_id", "nearest_building_id"], ifNotExists: true)
            try db.create(index: "idx_cached_orphans_campaign_address", on: "cached_address_orphans", columns: ["campaign_id", "address_id"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_client_link_cache_metadata_v1") { db in
            try db.create(table: "cached_client_link_batches", ifNotExists: true) { t in
                t.column("campaign_id", .text).primaryKey()
                t.column("asset_signature", .text).notNull()
                t.column("building_count", .integer).notNull().defaults(to: 0)
                t.column("address_count", .integer).notNull().defaults(to: 0)
                t.column("parcel_count", .integer).notNull().defaults(to: 0)
                t.column("link_count", .integer).notNull().defaults(to: 0)
                t.column("updated_at", .text)
                t.column("published_at", .text)
            }

            try db.create(index: "idx_cached_client_link_batches_signature", on: "cached_client_link_batches", columns: ["campaign_id", "asset_signature"], ifNotExists: true)
        }

        migrator.registerMigration("phase1_cached_links_one_address_assignment_v1") { db in
            try db.execute(sql: """
                DELETE FROM cached_building_address_links
                WHERE rowid NOT IN (
                    SELECT rowid
                    FROM (
                        SELECT
                            rowid,
                            ROW_NUMBER() OVER (
                                PARTITION BY campaign_id, address_id
                                ORDER BY
                                    CASE LOWER(COALESCE(source, ''))
                                        WHEN 'manual' THEN 40
                                        WHEN 'manual_fallback' THEN 30
                                        WHEN 'client_auto' THEN 20
                                        ELSE 0
                                    END DESC,
                                    COALESCE(confidence, 0) DESC,
                                    COALESCE(updated_at, '') DESC,
                                    id DESC
                            ) AS rn
                        FROM cached_building_address_links
                    )
                    WHERE rn = 1
                )
                """)

            try db.create(index: "idx_cached_links_campaign_address_unique", on: "cached_building_address_links", columns: ["campaign_id", "address_id"], unique: true, ifNotExists: true)
        }

        migrator.registerMigration("phase1_campaign_map_bundle_cache_v1") { db in
            try db.create(table: "cached_parcels", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("campaign_id", .text).notNull()
                t.column("external_id", .text)
                t.column("geometry_geojson", .text).notNull()
                t.column("properties_json", .text)
                t.column("payload_json", .text)
                t.column("updated_at", .text)
            }

            try db.create(table: "cached_campaign_map_bundles", ifNotExists: true) { t in
                t.column("campaign_id", .text).primaryKey()
                t.column("asset_signature", .text)
                t.column("source_version", .text)
                t.column("display_mode_hint", .text)
                t.column("links_status", .text)
                t.column("counts_json", .text)
                t.column("layer_fetched_at_json", .text)
                t.column("built_at", .text)
                t.column("expires_at", .text)
                t.column("updated_at", .text)
            }

            try db.create(index: "idx_cached_parcels_campaign_id", on: "cached_parcels", columns: ["campaign_id"], ifNotExists: true)
            try db.create(index: "idx_cached_map_bundles_expires", on: "cached_campaign_map_bundles", columns: ["campaign_id", "expires_at"], ifNotExists: true)
        }

        return migrator
    }
}
