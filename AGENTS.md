# notion-mcp-shared

This directory contains the public source package for a local shared Notion MCP HTTP service.

## Layout

- `install.sh` installs one user service on macOS or Linux.
- `notion-mcp-shared-server.sh` is the shared runtime launcher.
- `build-notion-bundle.sh` pins and builds the upstream Notion MCP server.
- `clients/` contains client configuration examples.
- `docs/bench/` contains measurement and read-only search tools.
- `docs/diagrams/` contains Mermaid sources and rendered SVGs.
- `upstream-prs/` contains local patch and PR-text drafts.

## Build and install

- Build a bundle into a new directory with `bash build-notion-bundle.sh NEW_DIRECTORY`. The directory
  appears only after a complete build; the installer reuses it only when it holds `bin/cli.mjs` and
  `scripts/notion-openapi.json`.
- Create the local service bearer with `./install.sh --secret`. The value is written and read
  literally, without shell quoting or unescaping; the installer rejects whitespace and control
  characters and protects only a directory it creates.
- Install the user service with `./install.sh`.
- The installer refuses to replace an existing launcher or service unit.
- Default service URL: `http://127.0.0.1:58983/mcp`.
- Do not put account tokens in service files or arguments.
- Configure each client with its own `NOTION_TOKEN` environment value.

## Documentation and checks

- Record measured values in `docs/bench/` before updating the README table or chart.
- Render Mermaid sources with `mmdc -i SOURCE.mmd -o OUTPUT.svg -t default -b transparent`.
- Record demo GIFs only with `vhs-safe demo/FILE.tape` and synthetic data.
- Check shell syntax with `bash -n install.sh notion-mcp-shared-server.sh`.
- Parse JSON examples with Python's `json` module.

## Safety

- Tests and benchmarks must not make Notion API calls unless a task explicitly requests one.
- Use a fake `NOTION_TOKEN` for MCP initialize and tools/list measurements. `docs/bench/measure.py`
  fixes that value and ignores the environment.
- Never print, log, commit, or include service bearer and Notion account tokens in output.
- Keep upstream patch drafts local; do not open PRs or publish packages without a separate owner request.
- Keep the existing personal service labels out of public examples.

## Code Review Rules

A change is a real defect when it:

- prints, logs, commits or writes a Notion token, service bearer or account value into a service file or an argument.
- makes the installer overwrite an existing launcher or service unit instead of refusing.
- changes the default service URL or port without updating the README and the client examples.
- breaks `bash -n install.sh notion-mcp-shared-server.sh`.
- makes a check or benchmark call the real Notion API, or run with a real token instead of a fake one.
- stops pinning the upstream Notion MCP version in the bundle build, or builds into an existing directory.

Not defects: wording, formatting, comment style, requested extra tests, or a renamed helper.
