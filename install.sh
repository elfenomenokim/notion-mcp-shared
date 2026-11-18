#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
HOME_DIR="${HOME:?HOME must be set}"
NAME=notion-mcp-shared
PORT=58983
SECRET="$HOME_DIR/.secrets/notion-mcp-shared.env"
DATA_DIR="$HOME_DIR/.local/share/notion-mcp-shared"
ACTION=install

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:?missing value for --name}"; shift 2 ;;
    --port) PORT="${2:?missing value for --port}"; shift 2 ;;
    --secret-file) SECRET="${2:?missing value for --secret-file}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?missing value for --data-dir}"; shift 2 ;;
    --secret) ACTION=secret; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo 'invalid service name' >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { echo 'port must be 1..65535' >&2; exit 2; }
BUNDLE="$DATA_DIR/runtime"
LAUNCHER="$HOME_DIR/.local/bin/$NAME"
UNIT_DIR="$HOME_DIR/.config/systemd/user"
UNIT="$UNIT_DIR/$NAME.service"

write_secret() {
  local secret_dir
  secret_dir="$(dirname "$SECRET")"
  umask 077
  # Create and protect only a directory this script creates. An existing parent,
  # such as $HOME or a shared directory, keeps the mode its owner chose.
  if [ ! -d "$secret_dir" ]; then
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"
  fi
  if [ -e "$SECRET" ]; then
    echo "Refusing to replace existing secret file: $SECRET" >&2
    exit 2
  fi
  read -r -s -p 'Service bearer token: ' bearer; printf '\n' >&2
  [ -n "$bearer" ] || { echo 'Bearer token is required' >&2; exit 2; }
  case "$bearer" in
    *[[:space:][:cntrl:]]*)
      echo 'Bearer token must not contain whitespace or control characters' >&2
      exit 2
      ;;
  esac
  # The launcher reads the value literally, so it is stored without shell
  # quoting and a '#' inside the token stays part of it.
  printf 'NOTION_MCP_AUTH_TOKEN=%s\n' "$bearer" > "$SECRET"
  unset bearer
  chmod 600 "$SECRET"
  echo "Created private secret file: $SECRET"
}

if [ "$ACTION" = secret ]; then
  write_secret
  exit 0
fi
[ -f "$SECRET" ] || { echo "Create the bearer file first: $0 --secret --secret-file '$SECRET'" >&2; exit 2; }
[ -x "$(command -v node || true)" ] || { echo 'Node.js is required' >&2; exit 2; }
NODE_BIN="$(python3 -c 'import os,shutil; print(os.path.realpath(shutil.which("node") or ""))')"
[ -x "$NODE_BIN" ] || { echo 'Could not resolve Node.js executable' >&2; exit 2; }
[ ! -e "$LAUNCHER" ] || { echo "Refusing to replace existing launcher: $LAUNCHER" >&2; exit 2; }
[ ! -e "$UNIT" ] || { echo "Refusing to replace existing service: $UNIT" >&2; exit 2; }

mkdir -p "$DATA_DIR" "$(dirname "$LAUNCHER")"
# A bundle is usable only when the build produced every file the service loads.
bundle_complete() {
  [ -s "$BUNDLE/bin/cli.mjs" ] && [ -s "$BUNDLE/scripts/notion-openapi.json" ]
}
if ! bundle_complete; then
  if [ -L "$BUNDLE" ] || { [ -e "$BUNDLE" ] && [ ! -d "$BUNDLE" ]; }; then
    echo "Refusing to replace unexpected runtime path: $BUNDLE" >&2
    exit 2
  fi
  if [ -d "$BUNDLE" ]; then
    # The builder accepts only a new path, and an interrupted build leaves this
    # directory behind. It is derived data owned by the installer.
    rm -rf -- "$BUNDLE"
  fi
  bash "$ROOT/build-notion-bundle.sh" "$BUNDLE"
fi
bundle_complete || { echo "Runtime bundle is incomplete: $BUNDLE" >&2; exit 2; }
install -m 700 "$ROOT/notion-mcp-shared-server.sh" "$LAUNCHER"

case "$(uname -s)" in
  Darwin)
    LABEL="com.notion.mcp-shared"
    [ "$NAME" = notion-mcp-shared ] || LABEL="com.notion.$NAME"
    PLIST_DIR="$HOME_DIR/Library/LaunchAgents"
    PLIST="$PLIST_DIR/$LABEL.plist"
    LOG_DIR="$HOME_DIR/Library/Logs/notion-mcp-shared"
    mkdir -p "$PLIST_DIR" "$LOG_DIR"
    [ ! -e "$PLIST" ] || { echo "Refusing to replace existing LaunchAgent: $PLIST" >&2; exit 2; }
    python3 - "$ROOT/com.notion.mcp-shared.plist" "$PLIST" "$LABEL" "$HOME_DIR" "$NAME" "$NODE_BIN" "$PORT" "$BUNDLE/bin/cli.mjs" "$SECRET" "$LOG_DIR" <<'PY'
import sys
from pathlib import Path
from xml.sax.saxutils import escape
source, target, label, home, name, node, port, runtime, secret, logs = sys.argv[1:]
text = Path(source).read_text(encoding='utf-8')
values = {
    '__LABEL__': label,
    '__HOME__': home,
    '__NAME__': name,
    '__NODE__': node,
    '__PORT__': port,
    '__RUNTIME__': runtime,
    '__SECRET__': secret,
    '__LOG_DIR__': logs,
}
if any(text.count(k) < 1 for k in values):
    raise SystemExit('unexpected LaunchAgent template placeholders')
for key, value in values.items():
    text = text.replace(key, escape(value))
Path(target).write_text(text, encoding='utf-8')
PY
    plutil -lint "$PLIST" >/dev/null
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    ;;
  Linux)
    mkdir -p "$UNIT_DIR"
    python3 - "$ROOT/notion-mcp-shared.service" "$UNIT" "$NAME" "$PORT" "$BUNDLE/bin/cli.mjs" "$SECRET" "$NODE_BIN" <<'PY'
import sys
from pathlib import Path
source, target, name, port, runtime, secret, node = sys.argv[1:]
text = Path(source).read_text(encoding='utf-8')
values = {'__NAME__': name, '__PORT__': port, '__RUNTIME__': runtime, '__SECRET__': secret, '__NODE__': node}
if any(text.count(k) != 1 for k in values):
    raise SystemExit('unexpected systemd unit template placeholders')
for key, value in values.items():
    # systemd expands % specifiers and parses backslash escapes in quoted values.
    value = value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')
    text = text.replace(key, value)
Path(target).write_text(text, encoding='utf-8')
PY
    chmod 600 "$UNIT"
    systemctl --user daemon-reload
    systemctl --user enable --now "$NAME.service"
    ;;
  *) echo 'Supported operating systems: macOS and Linux' >&2; exit 2 ;;
esac

echo "Installed $NAME at http://127.0.0.1:$PORT/mcp."
