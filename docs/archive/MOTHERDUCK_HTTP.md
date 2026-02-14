> **Archived.** The stack now uses Lambda + S3 for provisioning; MotherDuck is no longer used. See [ARCHITECTURE_PROVISION.md](../ARCHITECTURE_PROVISION.md).

# MotherDuck over HTTP (MCP API)

MotherDuck can be reached over HTTP via the MCP (Model Context Protocol) API. Use this when you can't use the DuckDB `md:` driver (e.g. serverless, backend services, or scripts that prefer plain HTTP).

## Endpoint

| | |
|--|--|
| **URL** | `https://api.motherduck.com/mcp` |
| **Method** | `POST` |

## Headers

| Header | Value |
|--------|--------|
| `Content-Type` | `application/json` |
| `Accept` | `application/json, text/event-stream` |
| `Authorization` | `Bearer <MOTHERDUCK_TOKEN>` |
| `MCP-Protocol-Version` | `2025-03-26` |

## Body (JSON-RPC 2.0)

Use the `tools/call` method with tool name `query` and arguments:

- **`database`** – MotherDuck database name (e.g. `my_db`, or `overture_na` for Overture address data).
- **`sql`** – Your DuckDB SQL. Use fully qualified names for data, e.g. `overture_na.addresses`, `overture_na.buildings`, `overture_na.roads`.

Example:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "query",
    "arguments": {
      "database": "overture_na",
      "sql": "SELECT gers_id, house_number, street_name, locality FROM overture_na.addresses LIMIT 5;"
    }
  },
  "id": 1234567890
}
```

## Token

- Get a token at [motherduck.com](https://motherduck.com) → Dashboard → Create token.
- Put it in `.env.local` as `MOTHERDUCK_TOKEN` for scripts; backend or iOS would read it from their own config (env, secrets, or Info.plist for dev only).

## Summary

**"Reach MotherDuck over HTTP"** = `POST https://api.motherduck.com/mcp` with:

1. `Authorization: Bearer <MOTHERDUCK_TOKEN>`
2. `MCP-Protocol-Version: 2025-03-26`
3. JSON-RPC body: `method: "tools/call"`, `params.name: "query"`, `params.arguments: { database, sql }`

No DuckDB driver or `md:` connection string required; any HTTP client can call this.
