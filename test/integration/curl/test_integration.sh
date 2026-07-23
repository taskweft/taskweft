#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

set -euo pipefail

BASE_URL="${MCP_BASE_URL:-http://localhost:20000/mcp/v1}"
DSL_FILE="${1:-test/integration/curl/blocks_world_dsl.ex}"

echo "Testing Taskweft MCP integration via curl..."
echo "DSL file: $DSL_FILE"
echo

# Test 1: Start MCP server
echo "Test 1: Start MCP server in background..."
mix taskweft.mcp > /tmp/taskweft_server.log 2>&1 &
SERVER_PID=$!
sleep 3

# Test 2: List tools
echo
echo "Test 2: List tools..."
curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }' | jq '.result.tools[] | .name' | grep -E '(plan|replan|validate|plan_dsl)' | sort
echo

# Test 3: Validate domain using DSL
echo
echo "Test 3: Validate domain using DSL..."
# Compile DSL to JSON-LD
JSON_LD=$(elixir --erl '-eval "Taskweft.Domain.SafeParser.parse_file(Param.input)" --eval 'param --args "$DSL_FILE")

if [ $? -eq 0 ]; then
  echo "Compiled DSL:"
  echo "$JSON_LD" | jq .
else
  echo "Failed to compile DSL"
  exit 1
fi

# Call validate tool
curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 2,
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"validate\",
      \"arguments\": {\"domain_json\": $JSON_LD}
    }
  }" | jq -r '.result.content[0].text' | head -5
echo

# Cleanup
echo
echo "Cleanup: stopping server..."
kill $SERVER_PID 2>/dev/null || true
sleep 1
echo "Done."