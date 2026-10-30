#!/usr/bin/env python3
"""Exercise the production outbox query in an isolated SQLite database."""
import json
import sqlite3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "WolfGrid/Offline/Repositories/OutboxRepository.swift").read_text()
query = source.split("static func fetchPending(in db: Database, now: String, limit: Int)", 1)[1].split('sql: """', 1)[1].split('"""', 1)[0]
db = sqlite3.connect(":memory:")
db.execute("""CREATE TABLE sync_outbox (
    id TEXT, entity_id TEXT, entity_type TEXT, operation TEXT, payload_json TEXT,
    synced_at TEXT, status TEXT, retry_after TEXT, dependency_key TEXT, created_at TEXT
)""")


def insert(identifier, operation, payload, key=None):
    encoded = payload if isinstance(payload, str) else json.dumps(payload)
    db.execute("INSERT INTO sync_outbox VALUES (?, ?, 'test', ?, ?, NULL, 'pending', NULL, ?, ?)",
               (identifier, identifier, operation, encoded, key or identifier, identifier))


def pending(limit=50):
    return [row[0] for row in db.execute(query, ("9999", limit))]


target = dict(campaignId="camp", addressId="addr", buildingId="building")
insert("01", "create_manual_address", target)
for index, operation in enumerate([
    "upsert_contact", "upsert_address_capture_metadata", "unlink_address_from_building",
    "delete_address", "move_address", "delete_building", "log_building_touch",
    "record_farm_address_outcome", "link_address_to_building",
]):
    insert(f"1{index}", operation, target)
insert("20", "upsert_contact", dict(addressId="other"))
insert("21", "upsert_address_status", dict(campaignId="other-campaign", addressIds=["addr"]))
insert("22", "upsert_address_status", dict(campaignId="camp", addressIds=["existing", "ADDR"]))
insert("23", "unrelated", "malformed")
insert("24", "upsert_contact", dict(addressId="ADDR"))  # Contact payload has no campaignId.
assert pending() == ["01", "20", "21", "23"]
assert pending(limit=1) == ["01"]
for status in ["conflict", "dead_letter", "failed", "processing", "blocked_upgrade"]:
    db.execute("UPDATE sync_outbox SET status = ? WHERE id = '01'", (status,))
    assert "22" not in pending() and "24" not in pending()
db.execute("UPDATE sync_outbox SET status = 'failed', retry_after = '99999' WHERE id = '01'")
assert pending() == ["20", "21", "23"]
db.execute("UPDATE sync_outbox SET synced_at = 'done' WHERE id = '01'")
assert len(pending()) == 14

# Existing ordering for successive writes to the same entity is retained.
insert("30", "upsert_contact", dict(addressId="other"), key="same-contact")
insert("31", "upsert_contact", dict(addressId="other"), key="same-contact")
assert "30" in pending() and "31" not in pending()
db.execute("UPDATE sync_outbox SET synced_at = 'done' WHERE id = '30'")
assert "31" in pending()
print("PASS: creation dependencies, contacts, multi-home status, removals, retries, malformed payloads, campaign isolation, and existing write order")
