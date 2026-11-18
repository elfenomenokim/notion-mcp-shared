#!/usr/bin/env bash
# Build the upstream 2.5.2 bundle with the cache-retention fix. Output is
# isolated; choosing and installing a runtime remains a separate operation.
# From the project root, prepare the versioned default without replacing the npm bundle:
# bash docs/products/dotfiles/mcp/build-notion-bundle.sh "$HOME/.local/share/feno-mcp/notion-2.5.2-deref-0.2.3-session-404"
# macOS: bash docs/products/dotfiles/bootstrap/notion-http-setup.sh renders and
# may restart the service. Linux: deploy the launcher and restart separately.
# Both retain the npm fallback; FENO_NOTION_MCP_RUNTIME overrides either choice.
# The output path appears only after a complete build, so an interrupted run
# leaves no directory that the next run would have to work around.
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 NEW_OUTPUT_DIRECTORY" >&2
  exit 2
fi
target="${1%/}"
[ -n "$target" ] || { echo 'usage: output directory must not be the root directory' >&2; exit 2; }
[ ! -e "$target" ] && [ ! -L "$target" ] || { echo "refusing existing output directory: $target" >&2; exit 2; }
mkdir -p "$(dirname "$target")"
partial="$target.partial.$$"
trap 'rm -rf -- "$partial"' EXIT HUP INT TERM
mkdir "$partial"
output="$(cd "$partial" && pwd -P)"
revision=730ae781ba28beeaf0865025a3f2ed4c25ea2387
archive="$output/source.tgz"
curl -fsSL "https://codeload.github.com/makenotion/notion-mcp-server/tar.gz/$revision" -o "$archive"
python3 - "$archive" <<'PY'
import hashlib, sys
from pathlib import Path
expected = '98894eb293e819c73592ca3bb3b6709e18d22a2e147f7ebbb32d1665522c2e28'
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() != expected:
    raise SystemExit('Notion source archive checksum mismatch')
PY
tar -xzf "$archive" -C "$output"
source_dir="$output/notion-mcp-server-$revision"
python3 - "$source_dir/package-lock.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
lock = json.loads(path.read_text())
entry = lock['packages']['node_modules/dereference-json-schema']
if entry['version'] != '0.2.1':
    raise SystemExit('Unexpected upstream dereference-json-schema version')
entry.update(version='0.2.3',
    resolved='https://registry.npmjs.org/dereference-json-schema/-/dereference-json-schema-0.2.3.tgz',
    integrity='sha512-CBVoEuf2tKhqnUhoKjvX4wo5NVxDSHxInqwExQfUNEK67aX+LPC27Vg+6CApi+KRebABJZAWhHBVoNpKfhMssg==')
path.write_text(json.dumps(lock, indent=2) + '\n')
PY
python3 - "$source_dir/scripts/start-server.ts" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
source = path.read_text()
# A stale session is rejected before transport.handleRequest can dispatch an
# operation. Missing session IDs retain upstream's 400 behavior.
old_post = """          res.status(400).json({
            jsonrpc: '2.0',
            error: {
              code: -32000,
              message: 'Bad Request: No valid session ID provided',"""
new_post = old_post.replace('res.status(400)', 'res.status(sessionId ? 404 : 400)')
old_other = "res.status(400).send('Invalid or missing session ID')"
new_other = "res.status(sessionId ? 404 : 400).send('Invalid or missing session ID')"
if source.count(old_post) != 1 or source.count(old_other) != 2:
    raise SystemExit('Unexpected upstream session handling; refusing to build')
path.write_text(source.replace(old_post, new_post).replace(old_other, new_other))
PY
(
  cd "$source_dir"
  npm ci
  npm run build
)
mkdir -p "$output/bin" "$output/scripts"
cp "$source_dir/bin/cli.mjs" "$output/bin/cli.mjs"
cp "$source_dir/scripts/notion-openapi.json" "$output/scripts/notion-openapi.json"
for required in bin/cli.mjs scripts/notion-openapi.json; do
  [ -s "$output/$required" ] || { echo "build did not produce $required" >&2; exit 2; }
done
mv -- "$output" "$target"
trap - EXIT HUP INT TERM
printf 'Built isolated runtime: %s/bin/cli.mjs\n' "$target"
