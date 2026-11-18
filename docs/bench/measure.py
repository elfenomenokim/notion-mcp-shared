#!/usr/bin/env python3
"""Measure N stdio Notion MCP processes and one shared HTTP process on Linux."""

import argparse
import concurrent.futures
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

# The measurement must never forward an account token. The value is fixed here and
# the environment is ignored, so an exported real NOTION_TOKEN cannot reach the
# stdio server.
BENCHMARK_NOTION_TOKEN = "benchmark-no-api-call"


def read_rss_kib(pid):
    try:
        output = subprocess.check_output(
            ["ps", "-o", "rss=", "-p", str(pid)], text=True, stderr=subprocess.DEVNULL
        ).strip()
        return int(output) if output else 0
    except (OSError, ValueError, subprocess.CalledProcessError):
        return 0


def read_json_line(process, wanted_id):
    while True:
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(f"stdio server exited with code {process.poll()}")
        message = json.loads(line)
        if message.get("id") == wanted_id:
            if "error" in message:
                raise RuntimeError("stdio MCP JSON-RPC error")
            return message.get("result", {})


def start_stdio(node, runtime):
    env = os.environ.copy()
    env["NOTION_TOKEN"] = BENCHMARK_NOTION_TOKEN
    process = subprocess.Popen(
        [node, runtime, "--transport", "stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
        env=env,
    )
    try:
        process.stdin.write(json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "notion-mcp-shared-bench", "version": "1"},
            },
        }) + "\n")
        process.stdin.flush()
        read_json_line(process, 1)
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        process.stdin.flush()
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}) + "\n")
        process.stdin.flush()
        result = read_json_line(process, 2)
        return process, [item.get("name", "") for item in result.get("tools", [])]
    except BaseException:
        process.terminate()
        process.wait(timeout=5)
        raise


def run_stdio_group(node, runtime, n):
    processes = []
    tool_names = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=n) as executor:
            futures = [executor.submit(start_stdio, node, runtime) for _ in range(n)]
            failure = None
            # Read every future, even after one fails: a started server is known to
            # this function only when its result is collected here, and the finally
            # block below can then stop it.
            for future in concurrent.futures.as_completed(futures):
                try:
                    process, count = future.result()
                except Exception as exc:
                    failure = failure or exc
                    continue
                processes.append(process)
                tool_names.append(count)
        if failure is not None:
            raise failure
        samples = []
        until = time.monotonic() + 1.0
        while time.monotonic() < until:
            samples.append(sum(read_rss_kib(p.pid) for p in processes if p.poll() is None))
            time.sleep(0.02)
        return {
            "processes": len(processes),
            "tools_list_ok": all(len(x) > 0 for x in tool_names),
            "tool_counts": [len(x) for x in tool_names],
            "tool_names": tool_names[0] if tool_names else [],
            "rss_peak_kib": max(samples, default=0),
            "rss_peak_mib": round(max(samples, default=0) / 1024, 2),
        }
    finally:
        for process in processes:
            process.terminate()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def post(url, payload, headers):
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            content = response.read().decode("utf-8", "replace")
            if "text/event-stream" in response.headers.get("Content-Type", ""):
                content = "\n".join(line[6:] for line in content.splitlines() if line.startswith("data: "))
            body = json.loads(content) if content.strip() else {}
            return response.status, response.headers, body
    except urllib.error.HTTPError as exc:
        # Do not include request headers, which contain bearer credentials.
        raise RuntimeError(f"HTTP MCP request returned status {exc.code}") from None


def one_http_session(endpoint, bearer, index):
    headers = {
        "Authorization": f"Bearer {bearer}",
        "Notion-Token": BENCHMARK_NOTION_TOKEN,
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    status, response_headers, initialized = post(endpoint, {
        "jsonrpc": "2.0", "id": index * 2 + 1, "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "notion-mcp-shared-bench", "version": "1"},
        },
    }, headers)
    if status != 200 or "error" in initialized:
        raise RuntimeError("HTTP MCP initialize failed")
    session_id = response_headers.get("Mcp-Session-Id")
    protocol = initialized.get("result", {}).get("protocolVersion", "2024-11-05")
    headers["MCP-Protocol-Version"] = protocol
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    post(endpoint, {"jsonrpc": "2.0", "method": "notifications/initialized"}, headers)
    status, _, listed = post(endpoint, {
        "jsonrpc": "2.0", "id": index * 2 + 2, "method": "tools/list", "params": {},
    }, headers)
    result = listed.get("result", {})
    count = len(result.get("tools", []))
    if status != 200 or count == 0 or "error" in listed:
        raise RuntimeError("HTTP MCP tools/list failed")
    if session_id:
        # Session close is a DELETE with no body.
        request = urllib.request.Request(endpoint, headers={
            "Authorization": f"Bearer {bearer}",
            "Mcp-Session-Id": session_id,
            "MCP-Protocol-Version": protocol,
        }, method="DELETE")
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                pass
        except urllib.error.HTTPError:
            pass
    return count, [item.get("name", "") for item in result.get("tools", [])]


def run_shared(endpoint, bearer, server_pid):
    responses = []
    samples = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(one_http_session, endpoint, bearer, i) for i in range(5)]
        while any(not f.done() for f in futures):
            samples.append(read_rss_kib(server_pid))
            time.sleep(0.02)
        for future in futures:
            responses.append(future.result())
    final = read_rss_kib(server_pid)
    samples.append(final)
    peak = max(samples, default=0)
    return {
        "processes": 1,
        "parallel_sessions": 5,
        "initialize_and_tools_list_ok": all(count > 0 for count, _ in responses),
        "tool_counts": [count for count, _ in responses],
        "tool_names": responses[0][1] if responses else [],
        "rss_peak_kib": peak,
        "rss_peak_mib": round(peak / 1024, 2),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--server-secret", required=True)
    parser.add_argument("--server-pid", required=True, type=int)
    parser.add_argument("--counts", nargs="+", type=int, default=[1, 3, 5])
    parser.add_argument("--output")
    args = parser.parse_args()
    bearer = None
    # The secret file stores the value literally, exactly as the launcher reads it.
    for raw in Path(args.server_secret).read_text().splitlines():
        line = raw.strip()
        if line.startswith("NOTION_MCP_AUTH_TOKEN="):
            bearer = line.split("=", 1)[1]
            break
    if not bearer:
        raise SystemExit("server bearer missing from private secret file")
    measurements = {
        "platform": "Ubuntu Linux",
        "runtime": Path(args.runtime).name,
        "endpoint": args.endpoint,
        "stdio": {},
    }
    for n in args.counts:
        measurements["stdio"][str(n)] = run_stdio_group(args.node, args.runtime, n)
    measurements["shared_http"] = run_shared(args.endpoint, bearer, args.server_pid)
    measurements["shared_http"].pop("processes", None)
    encoded = json.dumps(measurements, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(encoded)
    print(encoded, end="")


if __name__ == "__main__":
    main()
