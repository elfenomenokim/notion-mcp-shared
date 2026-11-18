# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The package is installed from git, so
entries are dated and no version number is attached.

## Unreleased

### Fixed

- `install.sh` accepts the LaunchAgent template's repeated placeholders, so the macOS install writes
  and starts the agent instead of exiting.
- The Linux unit receives the resolved Node executable, so an install whose Node comes from nvm or
  another user-local version manager can start.

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
