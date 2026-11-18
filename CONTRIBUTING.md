# Contributing to notion-mcp-shared

Fixes and reports are welcome. You do not need to ask before opening a pull request for a bug fix.

## Before you start

- **The service does not start:** open an
  [issue](https://github.com/elfenomenokim/notion-mcp-shared/issues/new/choose) with the installer
  output, the service status, your Node.js version and your OS. Never paste a token.
- **A client compatibility fix:** say which client, its version, and the request that failed.
- **A security problem:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Set up

```sh
git clone https://github.com/elfenomenokim/notion-mcp-shared
cd notion-mcp-shared
bash build-notion-bundle.sh /tmp/notion-mcp-bundle
bash -n install.sh notion-mcp-shared-server.sh
python3 -m json.tool clients/claude-code.json
```

The bundle build pins and builds the upstream Notion MCP server. Installation writes one user
service; the installer refuses to replace an existing launcher or unit.

## Rules a patch must keep

- No token in a service file, a plist, a unit, an argument or a log line. Each client passes its own
  `NOTION_TOKEN` per request.
- The service listens on loopback only.
- Benchmarks and tests use a placeholder token and make no Notion API call.
- The installer stays idempotent and refuses to overwrite; a half-finished install must not leave a
  launcher behind that the next run cannot replace.

## What a good patch has

- **The installer output and the service status** before and after, from a fresh machine or a fresh
  user account where you can make one.
- **A line under Unreleased** in [CHANGELOG.md](CHANGELOG.md) when a user will notice.
- **The platforms you did not test** written in the pull request. The Linux unit has been
  exercised on Ubuntu; the macOS LaunchAgent has not been exercised from this installer.

## Review

Every pull request runs an automatic DeepSeek review. Ask for another pass with `@codex review` or
`@claude review` in a comment. If a finding looks wrong, say why in the pull request.

## Licence

Contributions are licensed under the MIT licence in [LICENSE](LICENSE).
