# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The package is installed from git, so
entries are dated and no version number is attached.

## 2026-11-19

### Added

- README section "Official server vs this": the Notion tools are upstream's unmodified 24-tool
  surface, so this project is a thin layer. The section lists what it adds (user service unit,
  secret-file handling, fail-closed start, two upstream patches), what it does not add (OAuth,
  semantic search, connected-app search, hosted operation), upstream's maintenance status, and the
  condition that makes this project redundant.

### Changed

- Verified against upstream `main` on 2026-11-19: both patched defects remain. A supplied stale
  session ID still answers HTTP 400, and the lockfile still resolves `dereference-json-schema`
  `0.2.1`. Upstream 2.6.0 fixed the schema leak at the spec identity cache instead (#335). No code
  change.
- The bundle pin moves to upstream 2.6.1 (commit `cf16e5c2`, npm 2026-10-29). The launcher needs no
  change: 2.6.1 keeps `--transport http`, `--host`, `--port`, `ENABLE_TOKEN_PASSTHROUGH` and the
  `Notion-Token` header. Its OpenAPI spec is byte-identical to 2.5.2, so the tool surface stays at
  24 tools. 2.6.1 rejects file-upload operations and drops the client's local file reads; the pinned
  spec defines no multipart operation, so no tool changes behavior.
- `build-notion-bundle.sh` no longer patches `package-lock.json`. Upstream 2.6.0 fixed the schema
  retention at the spec identity cache (#335), so the `dereference-json-schema` 0.2.3 move is no
  longer needed. The stale-session patch is unchanged and still applies.
- The macOS service and its launcher chain select the 2.6.1 bundle; the 2.5.2 bundle stays as the
  fallback.

## 2026-11-18

### Fixed

- `install.sh` accepts the LaunchAgent template's repeated placeholders, so the macOS install writes
  and starts the agent instead of exiting.
- The Linux unit receives the resolved Node executable, so an install whose Node comes from nvm or
  another user-local version manager can start.
- The launcher reads the stored bearer literally instead of shell-unquoting it, so a token that
  contains `#` is no longer cut off at that character and the service no longer answers every client
  with 401. `install.sh --secret` writes the value without quoting and rejects whitespace and control
  characters, and both benchmark tools read the same file the same way.
- `install.sh --secret` creates and protects only a directory it creates. An existing parent, such as
  `$HOME` for `--secret-file ~/x.env`, keeps its mode.
- `build-notion-bundle.sh` builds into a temporary directory and moves it to the requested path only
  after `bin/cli.mjs` and `scripts/notion-openapi.json` exist, so an interrupted build leaves no
  directory behind. The installer rebuilds a runtime directory left by an interrupted build and
  refuses to install from a bundle that is missing either file.
- The benchmark sends the fixed placeholder token `benchmark-no-api-call` and ignores `NOTION_TOKEN`
  in the environment, so an exported account token cannot reach the stdio server.
- The benchmark stops every stdio server it started when one of them fails to start.

## 2026-11-17

### Added

- First public release: a loopback HTTP service that keeps one Notion MCP server process for
  several AI clients.
- Installer for one user service on macOS (LaunchAgent) and Linux (`systemd --user`).
- Client examples for Claude Code, Codex, Pi, Antigravity and Kimi Code; each client passes its own
  `NOTION_TOKEN`.
- Bundle build script that pins and builds the upstream Notion MCP server.
- Two compatibility patches for upstream, with reproduction steps and draft PR text.
- Saved Linux measurement: five stdio processes at 452.17 MiB against one shared process at
  84.64 MiB.
