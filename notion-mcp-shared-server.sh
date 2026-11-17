#!/bin/bash
# notion-mcp-shared-server.sh — shared Notion MCP HTTP service launcher
#
# One loopback service replaces per-session stdio Notion MCP servers across
# Claude Code and Codex. Clients select their Notion account per request with a
# `Notion-Token` header; this process must therefore NOT hold an account token.
#
# Two independent auth axes:
#   server access : NOTION_MCP_AUTH_TOKEN (Authorization: Bearer) — this file loads it
#   Notion account: NOTION_TOKEN per request header — NEVER loaded here
#
# Started by a per-user launchd or systemd service. Never run resident `npx`.
# Source package: notion-mcp-shared | Installed: ~/.local/bin/notion-mcp-shared

set -euo pipefail

PORT="${NOTION_MCP_SHARED_PORT:-58983}"
HOST="127.0.0.1"
RUNTIME="${NOTION_MCP_SHARED_RUNTIME:-$HOME/.local/share/notion-mcp-shared/runtime/bin/cli.mjs}"
SECRET="${NOTION_MCP_SHARED_SECRET:-$HOME/.secrets/notion-mcp-shared.env}"

# Fail closed: inherited credentials would either select a default account or
# silently replace the intended server bearer.
unset AUTH_TOKEN NOTION_MCP_AUTH_TOKEN NOTION_TOKEN OPENAPI_MCP_HEADERS NOTION_API_TOKEN

[ -f "$RUNTIME" ] || { echo "FATAL: runtime missing: $RUNTIME" >&2; exit 78; }
[ -f "$SECRET" ]  || { echo "FATAL: secret missing: $SECRET" >&2; exit 78; }

# Read exactly one allowed assignment without sourcing shell code. The parser
# also rejects symlinks, non-owner files, group/world access, and hard links.
NOTION_MCP_AUTH_TOKEN="$(python3 - "$SECRET" <<'PY'
import os
import shlex
import stat
import sys

path = sys.argv[1]
if not hasattr(os, "O_NOFOLLOW"):
    print("FATAL: O_NOFOLLOW unavailable; refusing secret open", file=sys.stderr)
    raise SystemExit(78)
try:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
except OSError as exc:
    print(f"FATAL: cannot open secret ({type(exc).__name__})", file=sys.stderr)
    raise SystemExit(78)

meta = os.fstat(fd)
if not stat.S_ISREG(meta.st_mode):
    os.close(fd)
    print("FATAL: secret must be a regular file", file=sys.stderr)
    raise SystemExit(78)
if meta.st_uid != os.getuid():
    os.close(fd)
    print("FATAL: secret must be owned by the current user", file=sys.stderr)
    raise SystemExit(78)
if stat.S_IMODE(meta.st_mode) & 0o077:
    os.close(fd)
    print("FATAL: secret permissions must be 0600 or stricter", file=sys.stderr)
    raise SystemExit(78)
if meta.st_nlink != 1:
    os.close(fd)
    print("FATAL: secret must have exactly one hard link", file=sys.stderr)
    raise SystemExit(78)

try:
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        lines = stream.read().splitlines()
except (OSError, UnicodeError) as exc:
    print(f"FATAL: cannot read secret ({type(exc).__name__})", file=sys.stderr)
    raise SystemExit(78)

value = None
for lineno, raw in enumerate(lines, 1):
    stripped = raw.strip()
    if not stripped or stripped.startswith("#"):
        continue
    try:
        parts = shlex.split(stripped, comments=True, posix=True)
    except ValueError:
        print(f"FATAL: invalid secret syntax at line {lineno}", file=sys.stderr)
        raise SystemExit(78)
    if parts and parts[0] == "export":
        parts = parts[1:]
    if len(parts) != 1 or "=" not in parts[0]:
        print(f"FATAL: invalid secret assignment at line {lineno}", file=sys.stderr)
        raise SystemExit(78)
    key, candidate = parts[0].split("=", 1)
    if key != "NOTION_MCP_AUTH_TOKEN":
        print(f"FATAL: disallowed secret key at line {lineno}", file=sys.stderr)
        raise SystemExit(78)
    if value is not None:
        print("FATAL: duplicate NOTION_MCP_AUTH_TOKEN assignment", file=sys.stderr)
        raise SystemExit(78)
    value = candidate

if not value:
    print("FATAL: NOTION_MCP_AUTH_TOKEN unset", file=sys.stderr)
    raise SystemExit(78)
if "\n" in value or "\x00" in value:
    print("FATAL: invalid NOTION_MCP_AUTH_TOKEN value", file=sys.stderr)
    raise SystemExit(78)
sys.stdout.write(value)
PY
)"

NODE_BIN="${NOTION_MCP_SHARED_NODE_BIN:-$(command -v node)}"
[ -n "$NODE_BIN" ] || { echo "FATAL: node not found" >&2; exit 78; }

# Pass the bearer through the environment, never argv: argv is world-readable in `ps`.
export AUTH_TOKEN="$NOTION_MCP_AUTH_TOKEN"
export ENABLE_TOKEN_PASSTHROUGH=true

echo "starting Notion MCP shared service on ${HOST}:${PORT} (token passthrough, no account token)"
exec "$NODE_BIN" "$RUNTIME" \
  --transport http \
  --host "$HOST" \
  --port "$PORT"
