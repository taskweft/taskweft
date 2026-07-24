#!/usr/bin/env python3
"""MCP Streamable HTTP client to verify Taskweft MCP server works."""

import httpx
import json
import sys
import time

HOST = "127.0.0.1"
PORT = 51737
BASE = f"http://{HOST}:{PORT}"

DSL_DOMAIN = """defmodule BlocksWorld do
  use Taskweft.DSL

  @name "blocks_world"

  @variables %{
    pos: %{type: :ref, init: %{a: "table", b: "table", c: "table"}},
    clear: %{type: :bool, init: %{a: true, b: true, c: true}}
  }

  @actions %{
    a_pickup: %{
      params: [:block],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer_get: "/pos/{block}"}, b: "table"}},
        %{eval: %{type: "math/eq", a: %{pointer_get: "/clear/{block}"}, b: true}},
        %{pointer_set: "/pos/{block}", value: "hand"},
        %{pointer_set: "/holding/hand", value: "{block}"}
      ]
    }
  }

  @methods %{
    top: %{
      params: [],
      alternatives: [
        %{name: "start", subtasks: [["a_pickup", "a"], ["a_pickup", "b"]]}
      ]
    }
  }

  @todo_list [
    ["top"]
  ]
end
"""


def main():
    print(f"Connecting to Taskweft MCP at {BASE}...")

    with httpx.Client(timeout=30.0) as client:
        # --- Initialize ---
        print("\n>>> Sending initialize...")
        req = {
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "mcp-qa", "version": "0.1.0"},
            },
            "id": 1,
        }
        resp = client.post(BASE, json=req, headers={"Content-Type": "application/json"})
        print(f"<<< Status: {resp.status_code}")
        print(f"<<< Body: {resp.text[:500]}")
        if resp.status_code != 200:
            print("ERROR: Initialize failed")
            sys.exit(1)

        init_result = resp.json()
        print(f"<<< Parsed: {json.dumps(init_result, indent=2)[:300]}")

        # --- List tools ---
        print("\n>>> Sending tools/list...")
        req2 = {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "params": {},
            "id": 2,
        }
        resp = client.post(BASE, json=req2, headers={"Content-Type": "application/json"})
        print(f"<<< Status: {resp.status_code}")
        print(f"<<< Body: {resp.text[:500]}")
        if resp.status_code != 200:
            print("ERROR: tools/list failed")
            sys.exit(1)

        tools = resp.json()
        print(f"<<< Tools: {json.dumps(tools, indent=2)[:500]}")

        # --- Call plan tool with DSL ---
        print("\n>>> Sending tools/call (plan)...")
        req3 = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "plan",
                "arguments": {"domain_dsl": DSL_DOMAIN, "format": "dsl"},
            },
            "id": 3,
        }
        resp = client.post(BASE, json=req3, headers={"Content-Type": "application/json"})
        print(f"<<< Status: {resp.status_code}")
        print(f"<<< Body: {resp.text[:800]}")
        if resp.status_code != 200:
            print("ERROR: Plan tool call failed")
            sys.exit(1)

        plan = resp.json()
        content_list = plan.get("result", {}).get("content", [])
        if content_list:
            text = content_list[0].get("text", "")
            print(f"<<< Plan result (first 500): {text[:500]}")
        else:
            print(f"<<< Full response: {json.dumps(plan, indent=2)[:500]}")

        # --- Call validate tool ---
        print("\n>>> Sending tools/call (validate)...")
        req4 = {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "validate",
                "arguments": {"domain_dsl": DSL_DOMAIN, "format": "dsl"},
            },
            "id": 4,
        }
        resp = client.post(BASE, json=req4, headers={"Content-Type": "application/json"})
        print(f"<<< Status: {resp.status_code}")
        print(f"<<< Body: {resp.text[:800]}")
        if resp.status_code != 200:
            print("ERROR: Validate tool call failed")
            sys.exit(1)

    print("\n✅ All checks passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())