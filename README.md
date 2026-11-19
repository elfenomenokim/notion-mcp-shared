<div align="center">

<img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/logo.svg" width="96" height="96" alt="notion-mcp-shared: one service serving several clients">

# notion-mcp-shared
[한국어](README.ko.md)

A local HTTP service lets multiple AI clients share one Notion MCP server process.

Node.js · Python 3

[![license](https://img.shields.io/github/license/elfenomenokim/notion-mcp-shared)](https://github.com/elfenomenokim/notion-mcp-shared/blob/main/LICENSE)

Five stdio clients hold 452.17 MiB; one shared process holds 84.64 MiB with the same five sessions, from the saved Linux measurement.

[Install](#install) · [Architecture](#architecture) · [Official server vs this](#official-server-vs-this) · [Client configuration](#client-configuration)

</div>

<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.svg" alt="Several client sessions send requests through one local Notion MCP server">
</picture>
</p>

## Install

Requirements: Node.js, npm, Python 3, curl, tar, and a Notion integration token.

```sh
./install.sh --secret
./install.sh
```

The first command stores a local service bearer in a mode-600 file. The value is stored literally, so a token may contain `#`. Configure each client with its own `NOTION_TOKEN`; the service passes that token per request. The service listens on `http://127.0.0.1:58983/mcp` by default.

The installer refuses to replace an existing launcher or service unit. If a bundle build is interrupted, run `./install.sh` again: it rebuilds the runtime directory and publishes the new bundle only after a complete build.

The installer supports macOS LaunchAgent and Linux `systemd --user` services. The Linux installer was exercised on an Ubuntu host. The existing macOS LaunchAgent remains on its prior installation; this public installer has not been exercised on macOS.

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.dark.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.svg" alt="Client sessions send MCP requests to one loopback service, which forwards each Notion token to the Notion API">
</picture>

The `Authorization: Bearer` value authenticates clients to the local service. The `Notion-Token` header selects the Notion account for each request. The service does not keep an account token.

## Official server vs this

The Notion tools come from [`makenotion/notion-mcp-server`](https://github.com/makenotion/notion-mcp-server), with its OpenAPI spec unchanged: 24 tools, the same set as upstream 2.5.2 and as `main` on 2026-11-19. This project adds the process, service and secret handling around that server. It is a thin layer on the official server, not a second Notion client.

| | Official server | This project |
|---|---|---|
| Notion tools | 24 from its OpenAPI spec | the same 24, unchanged |
| Transport | stdio, Streamable HTTP | Streamable HTTP |
| Client auth | `--auth-token` or `AUTH_TOKEN` | bearer from a `0600` file, passed in the environment |
| Account per request | `--enable-token-passthrough`, `Notion-Token` header | the same |
| Process lifetime | you start and stop it | launchd or systemd user service |
| Upstream fixes | — | two patches in the pinned bundle |

This project adds:

- One user service unit with an absolute Node path, instead of a process that each session starts.
- A bearer read literally from a file after a no-follow, owner, `0600` and single-hard-link check, then passed in the environment. The value never appears in `ps` or in an `--auth-token` argument. Inherited `NOTION_TOKEN` and `AUTH_TOKEN` are unset before start, so the service cannot answer for an unintended account.
- A fail-closed start: exit 78 when the runtime, the secret or Node is missing.
- Two fixes that upstream `main` still does not carry. A supplied session ID that no longer exists returns HTTP 404, which tells a Streamable HTTP client to initialize again; upstream answers 400 and the client retries the same request. The pinned `dereference-json-schema` release moves from `0.2.1` to `0.2.3`.
- Client examples and the measurement below.

It does not add OAuth, semantic search, connected-app search, Markdown-native page editing or hosted operation. Notion's supported path for those is [Remote Notion MCP](https://developers.notion.com/docs/mcp), which this project cannot replace or self-host.

Upstream status, checked 2026-11-19: the repository README says the self-hosted server is no longer actively maintained or supported, that issues and pull requests are not actively monitored, and that the repository may be sunset. npm still publishes releases: 2.6.0 on 2026-10-28 and 2.6.1 on 2026-10-29.

Run the official server directly when one client with one integration needs the tools:

```sh
npx @notionhq/notion-mcp-server --transport http --auth-token "$(cat ~/.secrets/notion.env)"
```

Use this project when several sessions share one account set and each client sends its own Notion token.

This project is superseded when upstream returns 404 for a stale supplied session, fixes the schema retention and ships a user service unit with the same secret handling. 2.6.0 already fixed the schema leak at the spec identity cache (upstream #335), so the lockfile patch drops out of that move. Check a newer revision in the two session status lines of `scripts/start-server.ts` and in the `dereference-json-schema` entry of `package-lock.json`.

## Client configuration

Copy the matching example from `clients/`: Claude Code, Codex, Pi, Antigravity, or Kimi Code. The bearer token and `NOTION_TOKEN` must be available in the client process environment.

## Measurements

On a Linux host with Node.js v22.23.5, each stdio process completed MCP `initialize` and `tools/list`. The shared server completed the same calls for five concurrent HTTP sessions. Each response listed 24 tools. RSS is the peak process total sampled during and for one second after each run.

| stdio MCP processes | Total stdio RSS | Shared server RSS with 5 HTTP sessions |
|---:|---:|---:|
| 1 | 90.50 MiB | 84.64 MiB |
| 3 | 271.04 MiB | 84.64 MiB |
| 5 | 452.17 MiB | 84.64 MiB |

The shared service used one Node process in every row. The measurements come from [`docs/bench/linux-2026-11-17.json`](docs/bench/linux-2026-11-17.json).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared-rss.dark.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared-rss.svg" alt="Measured Linux peak RSS: stdio processes use 90.50, 271.04, and 452.17 MiB for one, three, and five processes; the shared process uses 84.64 MiB with five concurrent HTTP sessions">
</picture>

Reproduce the process and concurrency measurement after installation:

```sh
server_pid=$(systemctl --user show notion-mcp-shared.service -p MainPID --value)
python3 docs/bench/measure.py \
  --node "$(command -v node)" \
  --runtime "$HOME/.local/share/notion-mcp-shared/runtime/bin/cli.mjs" \
  --endpoint http://127.0.0.1:58983/mcp \
  --server-secret "$HOME/.secrets/notion-mcp-shared.env" \
  --server-pid "$server_pid" --counts 1 3 5 \
  --output docs/bench/linux-2026-11-17.json
```

The benchmark sends the fixed placeholder token `benchmark-no-api-call` and ignores `NOTION_TOKEN` in the environment, so a real account token cannot reach the server. It lists tools only and makes no Notion API calls. One separate read-only `API-post-search` call through the test service succeeded. The test service and its temporary files were then removed.

## Upstream fixes

`upstream-prs/` contains two local patch files, reproduction steps, proposed branch names, and PR text for `makenotion/notion-mcp-server`. No PR is open.

## Limits

The service binds to loopback and is intended for one local user account. The bundle pins upstream 2.5.2 (commit `730ae781`) and applies the two documented compatibility fixes; moving the pin means re-deriving both patches against that revision. Demo data and demo credentials are synthetic.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the bundle build and the review process.

## License

MIT. This project is an unofficial community tool and is not affiliated with Notion.
