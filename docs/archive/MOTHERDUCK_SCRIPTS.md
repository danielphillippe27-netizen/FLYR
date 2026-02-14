> **Archived.** The stack now uses Lambda + S3 for provisioning; MotherDuck scripts have been removed. See [ARCHITECTURE_PROVISION.md](../ARCHITECTURE_PROVISION.md).

# MotherDuck scripts (overture_na)

Scripts in this repo for one-time loading and testing MotherDuck `overture_na` (addresses, buildings, roads). Addresses in `overture_na.addresses` are populated from your private S3 address dataset (160M US addresses); buildings and roads in the same DB may come from Overture's public S3.

**Reach MotherDuck over HTTP:** See [MOTHERDUCK_HTTP.md](./MOTHERDUCK_HTTP.md) for the MCP API (`POST https://api.motherduck.com/mcp` with Bearer token and JSON-RPC `tools/call`). Use `npm run motherduck:test-mcp` to test via HTTP (no DuckDB driver).

## Environment

Create `.env.local` in the project root (gitignored). Copy from `.env.local.example` and fill in values.

| Variable | Purpose |
|----------|---------|
| `MOTHERDUCK_TOKEN` | **Required.** Get from [motherduck.com](https://motherduck.com) → Dashboard → Create token. |
| `AWS_ACCESS_KEY_ID` | Required for **load-overture-to-motherduck.ts** (S3 read). |
| `AWS_SECRET_ACCESS_KEY` | Required for load script (S3 read). |
| `FLYR_ADDRESSES_S3_BUCKET` | Optional. Default: `flyr-pro-addresses-2025`. |
| `FLYR_ADDRESSES_S3_REGION` | Optional. Default: `us-east-1`. |

## Commands

- **One-time load (create table and optionally load from S3):**
  ```bash
  npx tsx scripts/load-overture-to-motherduck.ts
  ```
  Creates database `overture_na` and table `addresses` if they do not exist. If AWS credentials are set, attempts to load from S3 parquet at `s3://${FLYR_ADDRESSES_S3_BUCKET}/**/*.parquet`; adjust the script if your S3 layout or format (e.g. CSV) differs.

- **Test connection (DuckDB driver):**
  ```bash
  npm run motherduck:test
  ```
  Uses `duckdb-async` with `md:overture_na`; verifies `MOTHERDUCK_TOKEN` and runs a sample query. Exits 0 on success, non-zero on failure.

- **Test connection (HTTP MCP API):**
  ```bash
  npm run motherduck:test-mcp
  ```
  Uses `POST https://api.motherduck.com/mcp` with Bearer token and JSON-RPC `tools/call` (no DuckDB driver). See [MOTHERDUCK_HTTP.md](./MOTHERDUCK_HTTP.md).

## Dependencies

Install with:

```bash
npm install
```

Scripts use `tsx`, `dotenv`, and `duckdb-async` (see `package.json` devDependencies). Run with `npx tsx` so no global install is required.
