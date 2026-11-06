#!/usr/bin/env python3
"""
Merge overlay/litvin-configuration.json (committed template) with env vars
and write the result to a new path. Env vars take precedence over template.

Env vars read:
  LITVIN_API_ID         -> api_id
  LITVIN_API_HASH       -> api_hash
  LITVIN_BUNDLE_ID      -> bundle_id (optional override)
  LITVIN_TEAM_ID        -> team_id (optional, signed builds only)
  LITVIN_APPSTORE_ID    -> appstore_id (optional)
  LITVIN_APP_CENTER_ID  -> app_center_id (optional)
"""
import json
import os
import sys
from pathlib import Path

MAP = {
    "LITVIN_API_ID": "api_id",
    "LITVIN_API_HASH": "api_hash",
    "LITVIN_BUNDLE_ID": "bundle_id",
    "LITVIN_TEAM_ID": "team_id",
    "LITVIN_APPSTORE_ID": "appstore_id",
    "LITVIN_APP_CENTER_ID": "app_center_id",
}

def main():
    if len(sys.argv) < 3:
        print("usage: build_config.py <template.json> <output.json>", file=sys.stderr)
        sys.exit(2)
    template = Path(sys.argv[1])
    output = Path(sys.argv[2])

    cfg = json.loads(template.read_text(encoding="utf-8"))
    cfg.pop("_note", None)

    for env, key in MAP.items():
        val = os.environ.get(env)
        if val:
            cfg[key] = val

    missing = [k for k in ("api_id", "api_hash") if not cfg.get(k) or str(cfg[k]).startswith("REPLACE_WITH")]
    if missing:
        print(f"ERROR: missing required credentials: {missing}", file=sys.stderr)
        print("Set LITVIN_API_ID and LITVIN_API_HASH as GitHub repo secrets, or export them locally.", file=sys.stderr)
        sys.exit(1)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    print(f"Wrote {output}")

if __name__ == "__main__":
    main()
