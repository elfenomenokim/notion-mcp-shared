# Upstream PR drafts

These are local patch and description drafts against `makenotion/notion-mcp-server` commit `730ae781ba28beeaf0865025a3f2ed4c25ea2387`. They are not branches pushed to GitHub and no PR was opened.

## 1. Refresh the vulnerable schema dereferencer

- Proposed branch: `fix/dereference-json-schema-cache-retention`
- Patch: `dereference-json-schema.patch`
- Reproduction: install the pinned dependency graph with `npm ci`; exercise repeated `tools/list` calls for the same Notion schema from a long-lived MCP session; compare heap growth and cache retention before and after the dependency update. The package's old `0.2.1` implementation retains dereferenced schema objects across repeated conversion.
- PR title: `fix: update dereference-json-schema cache retention`
- PR body: Update the locked `dereference-json-schema` release to 0.2.3. The older locked release retains dereferenced schema objects during repeated schema conversion in long-lived MCP sessions. Reproduce by running repeated `tools/list` requests against a single process and observing retained heap. This keeps the existing dependency range and updates the lockfile resolution only.

## 2. Return 404 for an expired session

- Proposed branch: `fix/http-404-for-stale-mcp-sessions`
- Patch: `stale-session-404.patch`
- Reproduction: start the HTTP server, initialize a session, stop and restart the server, then send a request with the previous `Mcp-Session-Id`; the current handler returns 400 although the client session is gone.
- PR title: `fix: return 404 for stale HTTP MCP sessions`
- PR body: Distinguish a stale supplied session ID from a missing session ID in the POST and DELETE handlers. A supplied ID that no longer exists returns HTTP 404, which tells Streamable HTTP clients to initialize a new session. Requests without a session ID retain the current HTTP 400 response.
