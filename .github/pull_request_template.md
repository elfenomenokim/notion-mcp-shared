## What and why

<!-- What was wrong or missing, and how this change fixes it. Link the issue: Fixes #123 -->

## How to check it

<!-- The commands that show the change working, with their output. -->

## Checklist

- [ ] `bash -n install.sh notion-mcp-shared-server.sh` passes
- [ ] `python3 -m json.tool clients/claude-code.json` parses
- [ ] A client completed `initialize` and `tools/list` against the service
- [ ] `CHANGELOG.md` has a line under Unreleased if users will notice the change
- [ ] Anything I could not test is written above (another OS, a browser, a router)
