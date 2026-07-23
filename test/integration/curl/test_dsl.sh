#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

# Integration test for Elixir DSL-based plan input

echo "=== Testing Elixir DSL-based Plan Input ==="

# Start MockServer MCP server
echo "Starting MockServer MCP server..."
MOCK_SERVER_PORT=3333 MIX_ENV=test mix taskweft.mcp &
MOCK_PID=$!

# Wait for server to start
sleep 3

# Test 1: Parse simple DSL domain
DSL_DOMAIN='name "test_domain"
variable :pos, type: :ref, init: %{a: "table"}
variable :holding, type: :bool, init: %{hand: false}
action :pickup, params: [:block], body: [pointer_set("/pos/{block}", "hand"), pointer_set("/holding/hand", "{block}")]
todo_list [[:pickup, :a]]'

echo -e "\nTest 1: Parse simple DSL domain"
echo "$DSL_DOMAIN" | curl -s -X POST http://localhost:$MOCK_PID/tools \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "plan",
      "arguments": {
        "domain_json": '"'$DSL_DOMAIN'"',
        "format": "dsl"
      }
    }
  }' | jq '.result.output' || echo "FAILED"

# Test 2: Parse DSL with method alternatives
DSL_METHODS='name "blocks_world"
variable :pos, type: :ref, init: %{a: "table", b: "hand"}
variable :clear, type: :bool, init: %{a: true, b: false}
action :pickup, params: [:block], body: [pointer_set("/pos/{block}", "hand")]
method :move, params: [:block, :dest], alternatives: [alt(:get_and_put, subtasks: [[:get, "{block}"], [:put, "{block}", "{dest}"]])]
todo_list [[:move, :a, :table]]'

echo -e "\nTest 2: Parse DSL with method alternatives"
echo "$DSL_METHODS" | curl -s -X POST http://localhost:$MOCK_PID/tools \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "plan",
      "arguments": {
        "domain_json": '"'$DSL_METHODS'"',
        "format": "dsl"
      }
    }
  }' | jq '.result.output' || echo "FAILED"

# Stop server
echo -e "\nStopping MockServer..."
kill $MOCK_PID 2>/dev/null || true

echo -e "\n=== All tests completed ==="