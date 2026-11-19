#!/usr/bin/env bash
# Build the upstream 2.6.1 bundle with the stale-session fix. Output is
# isolated; choosing and installing a runtime remains a separate operation.
# From the project root, prepare the versioned default without replacing the npm bundle:
# bash docs/products/dotfiles/mcp/build-notion-bundle.sh "$HOME/.local/share/feno-mcp/notion-2.6.1-session-404"
# Upstream 2.6.0 fixed the schema retention at the spec identity cache (#335), so this
# build no longer patches the lockfile's dereference-json-schema release.
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
revision=cf16e5c20bfbfb98ecec1227f210ef0ae3abebe5
archive="$output/source.tgz"
curl -fsSL "https://codeload.github.com/makenotion/notion-mcp-server/tar.gz/$revision" -o "$archive"
python3 - "$archive" <<'PY'
import hashlib, sys
from pathlib import Path
expected = 'bfc4ec6a56634e18a77cfe76c3db9dccb88560930b1964de0dab834718fdc424'
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() != expected:
    raise SystemExit('Notion source archive checksum mismatch')
PY
tar -xzf "$archive" -C "$output"
source_dir="$output/notion-mcp-server-$revision"
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
