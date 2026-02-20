#!/usr/bin/env python3
"""
Generate a JWT for App Store Connect API using your .p8 auth key.
Requires: pip install pyjwt cryptography

Usage:
  export APP_STORE_CONNECT_ISSUER_ID="your-issuer-id-uuid"
  python3 scripts/app_store_connect_jwt.py
  # Or with explicit key path:
  python3 scripts/app_store_connect_jwt.py /path/to/AuthKey_XXXXX.p8
"""
import os
import sys
from pathlib import Path

try:
    import jwt
except ImportError:
    print("Install: pip install pyjwt cryptography", file=sys.stderr)
    sys.exit(1)

# Key ID from your .p8 filename (e.g. AuthKey_MN2S8MNF4A.p8 -> MN2S8MNF4A)
KEY_ID = "MN2S8MNF4A"
# Issuer ID from App Store Connect → Users and Access → Integrations (top of page)
ISSUER_ID = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "")

# Default key path
DEFAULT_KEY_PATH = Path.home() / "Downloads" / "AuthKey_MN2S8MNF4A.p8"

USAGE = "Usage: python3 app_store_connect_jwt.py [key.p8] <ISSUER_ID>"


def main():
    args = sys.argv[1:]
    key_path = Path(args[0]) if args and not args[0].startswith("-") else DEFAULT_KEY_PATH
    issuer_id = None
    if len(args) >= 2:
        issuer_id = args[1]
    elif len(args) == 1 and len(args[0]) == 36 and "-" in args[0]:
        issuer_id = args[0]
        key_path = DEFAULT_KEY_PATH
    if issuer_id is None:
        issuer_id = ISSUER_ID

    if not key_path.exists():
        print(f"Key file not found: {key_path}", file=sys.stderr)
        print(USAGE, file=sys.stderr)
        sys.exit(1)

    if not issuer_id:
        print("Provide Issuer ID (App Store Connect → Users and Access → Integrations)", file=sys.stderr)
        print(USAGE, file=sys.stderr)
        sys.exit(1)

    with open(key_path) as f:
        private_key = f.read()

    # Apple: ES256, aud appstoreconnect-v1, max 20 min expiry
    payload = {
        "iss": issuer_id,
        "iat": __import__("time").time(),
        "exp": __import__("time").time() + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    token = jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )
    if hasattr(token, "decode"):
        token = token.decode("utf-8")
    print(token)


if __name__ == "__main__":
    main()
