#!/usr/bin/env python3
"""Run one read-only Notion search through the shared MCP HTTP service."""

import argparse
import json
import os
import shlex
import urllib.error
import urllib.request
from pathlib import Path


def post(url, payload, headers):
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            content = response.read().decode("utf-8", "replace")
            if "text/event-stream" in response.headers.get("Content-Type", ""):
                content = "\n".join(line[6:] for line in content.splitlines() if line.startswith("data: "))
            return response.status, response.headers, json.loads(content) if content.strip() else {}
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"MCP HTTP status {exc.code}") from None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--server-secret", required=True)
    parser.add_argument("--query", required=True)
    args = parser.parse_args()
    notion_token = os.environ.get("NOTION_TOKEN")
    if not notion_token:
        raise SystemExit("NOTION_TOKEN must be supplied in the environment")
    bearer = None
    for raw in Path(args.server_secret).read_text().splitlines():
        if raw.startswith("NOTION_MCP_AUTH_TOKEN="):
            bearer = shlex.split(raw.split("=", 1)[1])[0]
            break
    if not bearer:
        raise SystemExit("server bearer missing from private secret file")
    headers = {
        "Authorization": f"Bearer {bearer}",
        "Notion-Token": notion_token,
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    status, response_headers, initialized = post(args.endpoint, {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "notion-mcp-shared-check", "version": "1"},
        },
    }, headers)
    if status != 200 or "error" in initialized:
        raise SystemExit("initialize failed")
    session_id = response_headers.get("Mcp-Session-Id")
    protocol = initialized.get("result", {}).get("protocolVersion", "2024-11-05")
    headers["MCP-Protocol-Version"] = protocol
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    post(args.endpoint, {"jsonrpc": "2.0", "method": "notifications/initialized"}, headers)
    _, _, listed = post(args.endpoint, {
        "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {},
    }, headers)
    if "error" in listed:
        raise SystemExit("tools/list failed")
    tools = listed.get("result", {}).get("tools", [])
    tool = next((item for item in tools if item.get("name") == "API-post-search"), None)
    if not tool:
        raise SystemExit("No search tool is exposed by this server")
    schema = tool.get("inputSchema", {}).get("properties", {})
    if "query" not in schema:
        raise SystemExit("search tool has no query argument")
    _, _, called = post(args.endpoint, {
        "jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": tool["name"], "arguments": {"query": args.query}},
    }, headers)
    result = called.get("result", {})
    failed = bool(result.get("isError")) or "error" in called
    if session_id:
        request = urllib.request.Request(args.endpoint, headers={
            "Authorization": f"Bearer {bearer}",
            "Mcp-Session-Id": session_id,
            "MCP-Protocol-Version": protocol,
        }, method="DELETE")
        try:
            with urllib.request.urlopen(request, timeout=10):
                pass
        except urllib.error.HTTPError:
            pass
    print(json.dumps({
        "tool": tool["name"],
        "ok": not failed,
        "content_blocks": len(result.get("content", [])),
    }))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
