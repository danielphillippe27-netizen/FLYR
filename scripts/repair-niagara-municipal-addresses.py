#!/usr/bin/env python3

from __future__ import annotations

import argparse
import math
import os
import re
from pathlib import Path

import geopandas as gpd
import requests
from shapely.geometry import shape


REPO_ROOT = Path(__file__).resolve().parents[1]
MUNICIPAL_ROOT = REPO_ROOT.parent / "municipal_data"
NIAGARA_ADDRESS_SHP = (
    MUNICIPAL_ROOT
    / "raw"
    / "niagara_addresses"
    / "OpenData_Address_Points_-2290474320796275561"
    / "Address_Points.shp"
)
CAMPAIGN_IDS = [
    "a997450f-2cd3-4efe-9b0e-ad6d457b6dc5",
    "ac2af2dd-77de-4a4e-9e26-54b638cfb121",
]
INSERT_BATCH_SIZE = 500
MANUAL_LINK_PRESERVE_MAX_DISTANCE_METERS = 10


def load_env(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$", line)
        if not match or match.group(1).startswith("#"):
            continue
        value = match.group(2).strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        os.environ.setdefault(match.group(1), value)


def supabase_headers() -> dict[str, str]:
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }


def supabase_url(path: str) -> str:
    base = os.environ.get("SUPABASE_URL") or os.environ.get("NEXT_PUBLIC_SUPABASE_URL")
    if not base:
        raise RuntimeError("Missing SUPABASE_URL or NEXT_PUBLIC_SUPABASE_URL")
    return f"{base.rstrip('/')}{path}"


def request_json(method: str, path: str, **kwargs):
    response = requests.request(method, supabase_url(path), headers=supabase_headers(), **kwargs)
    if not response.ok:
        raise RuntimeError(f"{method} {path} failed: {response.status_code} {response.text}")
    if response.text:
        return response.json()
    return None


def fetch_campaigns() -> list[dict]:
    ids = ",".join(CAMPAIGN_IDS)
    return request_json(
        "GET",
        "/rest/v1/campaigns",
        params={
            "select": "id,name,bbox,territory_boundary",
            "id": f"in.({ids})",
        },
    )


def fetch_address_features(campaign_id: str) -> list[dict]:
    result = request_json(
        "POST",
        "/rest/v1/rpc/rpc_get_campaign_addresses",
        json={"p_campaign_id": campaign_id},
    )
    return result.get("features", []) if isinstance(result, dict) else []


def count_rows(table: str, **filters) -> int:
    params = {"select": "id"}
    for column, value in filters.items():
        params[column] = f"eq.{value}"
    response = requests.get(
        supabase_url(f"/rest/v1/{table}"),
        headers={**supabase_headers(), "Prefer": "count=exact"},
        params=params,
    )
    if not response.ok:
        raise RuntimeError(f"count {table} failed: {response.status_code} {response.text}")
    content_range = response.headers.get("content-range", "")
    if "/" in content_range:
        return int(content_range.rsplit("/", 1)[1])
    return len(response.json())


def clean_text(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    text = str(value).strip()
    return text or None


def clean_number(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip() or None


def municipal_street_name(row) -> str | None:
    parts = [
        clean_text(row.get("StreetName")),
        clean_text(row.get("StreetType")),
        clean_text(row.get("StreetDir")),
    ]
    street = " ".join(part for part in parts if part)
    return street or None


def municipal_address_rows(campaign: dict, gdf) -> list[dict]:
    min_lon, min_lat, max_lon, max_lat = campaign["bbox"]
    boundary = shape(campaign["territory_boundary"])
    candidates = gdf.cx[min_lon:max_lon, min_lat:max_lat]
    inside = candidates[candidates.geometry.within(boundary)].copy()
    rows = []

    for _, row in inside.iterrows():
        house_number = clean_number(row.get("StreetNo"))
        street_name = municipal_street_name(row)
        if not house_number or not street_name:
            continue
        formatted = f"{house_number} {street_name}"
        point = row.geometry
        gsmart_id = clean_number(row.get("GSmartID"))
        source_id = f"niagara_addresses:{gsmart_id}" if gsmart_id else f"niagara_addresses:{point.x:.8f}:{point.y:.8f}"
        rows.append(
            {
                "campaign_id": campaign["id"],
                "address": formatted,
                "formatted": formatted,
                "house_number": house_number,
                "street_name": street_name,
                "locality": clean_text(row.get("Municipali")) or "Niagara Region",
                "region": "ON",
                "postal_code": None,
                "source": "diamond",
                "gers_id": source_id,
                "source_id": source_id,
                "coordinate": {"lat": point.y, "lon": point.x},
                "geom": f"SRID=4326;POINT({point.x} {point.y})",
                "visited": False,
                "country": "CA",
            }
        )

    rows.sort(key=lambda item: item["formatted"].lower())
    return rows


def distance_meters(a: dict, b: dict) -> float:
    earth_radius = 6371000
    delta_lat = math.radians(b["lat"] - a["lat"])
    delta_lon = math.radians(b["lon"] - a["lon"])
    lat_a = math.radians(a["lat"])
    lat_b = math.radians(b["lat"])
    haversine = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat_a) * math.cos(lat_b) * math.sin(delta_lon / 2) ** 2
    )
    return 2 * earth_radius * math.asin(math.sqrt(haversine))


def nearest_municipal_row(point: dict, rows: list[dict], used_source_ids: set[str]):
    best = None
    for row in rows:
        if row["source_id"] in used_source_ids:
            continue
        distance = distance_meters(point, row["coordinate"])
        if best is None or distance < best["distance"]:
            best = {"row": row, "distance": distance}
    return best


def delete_rows(table: str, **filters) -> None:
    params = {}
    for column, value in filters.items():
        params[column] = f"eq.{value}"
    request_json("DELETE", f"/rest/v1/{table}", params=params)


def delete_addresses(address_ids: list[str]) -> None:
    for index in range(0, len(address_ids), INSERT_BATCH_SIZE):
        batch = ",".join(address_ids[index : index + INSERT_BATCH_SIZE])
        request_json("DELETE", "/rest/v1/campaign_addresses", params={"id": f"in.({batch})"})


def insert_addresses(rows: list[dict]) -> None:
    for index in range(0, len(rows), INSERT_BATCH_SIZE):
        request_json("POST", "/rest/v1/campaign_addresses", json=rows[index : index + INSERT_BATCH_SIZE])


def update_address(address_id: str, campaign_id: str, row: dict) -> None:
    payload = dict(row)
    payload.pop("campaign_id", None)
    request_json(
        "PATCH",
        "/rest/v1/campaign_addresses",
        params={"id": f"eq.{address_id}", "campaign_id": f"eq.{campaign_id}"},
        json=payload,
    )


def auto_link(campaign_id: str):
    return request_json(
        "POST",
        "/rest/v1/rpc/auto_link_campaign_addresses",
        json={"p_campaign_id": campaign_id},
    )


def repair_campaign(campaign: dict, rows: list[dict], apply: bool, force: bool) -> None:
    features = fetch_address_features(campaign["id"])
    current_address_ids = [feature["id"] for feature in features if feature.get("id")]
    existing_addresses = count_rows("campaign_addresses", campaign_id=campaign["id"])
    existing_statuses = count_rows("address_statuses", campaign_id=campaign["id"])
    existing_links = count_rows("building_address_links", campaign_id=campaign["id"])
    visited = count_rows("campaign_addresses", campaign_id=campaign["id"], visited="true")
    manual_links = request_json(
        "GET",
        "/rest/v1/building_address_links",
        params={
            "select": "address_id",
            "campaign_id": f"eq.{campaign['id']}",
            "link_source": "eq.manual",
        },
    )

    used_source_ids = set()
    manual_preserves = []
    for link in manual_links:
        feature = next((candidate for candidate in features if candidate.get("id") == link["address_id"]), None)
        coordinates = feature.get("geometry", {}).get("coordinates") if feature else None
        if not coordinates or len(coordinates) < 2:
            continue
        nearest = nearest_municipal_row(
            {"lon": float(coordinates[0]), "lat": float(coordinates[1])},
            rows,
            used_source_ids,
        )
        if not nearest:
            continue
        used_source_ids.add(nearest["row"]["source_id"])
        manual_preserves.append(
            {
                "address_id": link["address_id"],
                "before": feature.get("properties", {}).get("formatted", link["address_id"]),
                "row": nearest["row"],
                "distance": nearest["distance"],
            }
        )

    print(
        f"{campaign['name']} ({campaign['id']}): existing={existing_addresses}, municipal={len(rows)}, "
        f"statuses={existing_statuses}, visited={visited}, links={existing_links}, manualLinks={len(manual_links)}"
    )
    print("  sample municipal:", "; ".join(row["formatted"] for row in rows[:8]))
    for preserve in manual_preserves:
        print(
            f"  preserve manual link: {preserve['before']} -> {preserve['row']['formatted']} "
            f"({preserve['distance']:.1f}m)"
        )

    if not apply:
        return

    unsafe = [
        preserve
        for preserve in manual_preserves
        if preserve["distance"] > MANUAL_LINK_PRESERVE_MAX_DISTANCE_METERS
    ]
    if not force and (visited > 0 or existing_statuses > 0 or unsafe):
        raise RuntimeError(f"Refusing to repair {campaign['name']}: state or manual links need review.")

    delete_rows("building_address_links", campaign_id=campaign["id"], link_source="auto")
    manual_address_ids = {preserve["address_id"] for preserve in manual_preserves}
    delete_addresses([address_id for address_id in current_address_ids if address_id not in manual_address_ids])

    for preserve in manual_preserves:
        update_address(preserve["address_id"], campaign["id"], preserve["row"])

    insert_addresses([row for row in rows if row["source_id"] not in used_source_ids])
    delete_rows("campaign_polished_building_features", campaign_id=campaign["id"])
    link_result = auto_link(campaign["id"])
    print(
        f"  repaired: addresses={count_rows('campaign_addresses', campaign_id=campaign['id'])}, "
        f"links={count_rows('building_address_links', campaign_id=campaign['id'])}, autoLink={link_result}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    load_env(REPO_ROOT / "backend-api-routes" / ".env.local")
    load_env(REPO_ROOT / "backend-api-routes" / ".env")
    if "SUPABASE_SERVICE_ROLE_KEY" not in os.environ:
        raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY")

    gdf = gpd.read_file(NIAGARA_ADDRESS_SHP).to_crs("EPSG:4326")
    campaigns = fetch_campaigns()
    by_id = {campaign["id"]: campaign for campaign in campaigns}

    print("Applying municipal repair." if args.apply else "Dry run only. Add --apply to write changes.")
    for campaign_id in CAMPAIGN_IDS:
        campaign = by_id[campaign_id]
        rows = municipal_address_rows(campaign, gdf)
        repair_campaign(campaign, rows, args.apply, args.force)


if __name__ == "__main__":
    main()
