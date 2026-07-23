#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

# Integration test for DSL-based plan input

echo "=== Testing DSL-based Plan Input ==="

# Start MockServer for MCP tests
echo "Starting MockServer..."
mockserver -port 1080 -verbose > /tmp/mockserver.log 2>&1 &
MOCKSERVER_PID=$!
sleep 3

# Test with curl - direct DSL compilation
echo ""
echo "Test 1: Direct DSL compilation via MCP endpoint"
curl -X GET "http://localhost:1080/plan?domain=%7B%22name%22%3A%22test-domain%22%2C%22variables%22%3A%5B%7B%22name%22%3A%22loc%22%2C%22type%22%3A%22ref%22%2C%22init%22%3A%22base%22%7D%5D%2C%22actions%22%3A%7B%22move%22%3A%7B%22params%22%3A%5B%22agent%22%5D%2C%22body%22%3A%5B%7B%22type%22%3A%22pointer/set%22%2C%22pointer%22%3A%22loc%22%2C%22value%22%3A%22city%22%7D%5D%7D%7D%2C%22methods%22%3A%7B%22move%22%3A%7B%22params%22%3A%5B%22agent%22%5D%2C%22alternatives%22%3A%5B%7B%22name%22%3A%22walk%22%2C%22check%22%3A%5B%7B%22type%22%3A%22rebac%2Fcheck%22%2C%22subject%22%3A%22%7Bagent%7D%22%2C%22rel%22%3A%22has_capability%22%2C%22object%22%3A%22fly%22%7D%5D%2C%22subtasks%22%3A%5B%5B%22move%22%5D%5D%7D%5D%7D%7D%2C%22todo_list%22%3A%5B%5B%22move%22%5D%5D%7D" -H "Content-Type: application/json" 2>/dev/null | jq .

# Stop MockServer
echo ""
echo "Stopping MockServer (PID: $MOCKSERVER_PID)"
kill $MOCKSERVER_PID 2>/dev/null || true

echo ""
echo "=== Integration test complete ==="