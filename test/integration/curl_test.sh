#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

set -euo pipefail

BASE_URL="${MCP_BASE_URL:-http://localhost:20000/mcp/v1}"

echo "Testing Taskweft MCP integration via curl..."
echo

# Test 1: Start MCP server
echo "Test 1: Start MCP server..."
mix taskweft.mcp &
SERVER_PID=$!
sleep 2

# Test 2: List tools
echo "Test 2: List tools..."
curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }' | jq '.result.tools[] | .name' | grep -E '(plan|replan|validate|plan_dsl)' | sort