# GitHub Actions Integration Test Setup

## Workflow Details

The `.github/workflows/integration-test.yml` workflow runs on push and pull_request to main/develop branches.

### Test Coverage

1. **Unit Tests** - `mix test`
   - All ExUnit tests
   
2. **Property Tests** - `mix test --include property`
   - PropCheck property-based tests

3. **MCP Integration Tests** (curl-based)
   - **tools/list** - Verifies plan_dsl tool is registered
   - **tools/call** - Tests validate tool with JSON-LD domain
   - **tools/call** - Tests plan tool with JSON-LD domain
   - Logs saved on failure for debugging

### How It Works

```
┌─────────────────┐
│ GitHub Actions  │
└────────┬────────┘
         │
    ┌────▼────┐
    │  Setup  │ (Elixir, deps, cache)
    └────┬────┘
         │
    ┌────▼────┐
    │ Compile │ (mix compile)
    └────┬────┘
         │
    ┌────▼────┐
    │  Unit   │ (mix test)
    └────┬────┘
         │
    ┌────▼────┐
    │  MCP    │ (start server in background)
    │ Server  │
    └────┬────┘
         │
    ┌────▼─────┬──────────────────┐
    │ curl     │ curl              │
    │ tools/   │ tools/call        │
    │ list     │ validate          │
    │          │ plan              │
    └────┬─────┴──────────────────┘
         │
    ┌────▼────┐
    │ Cleanup │ (kill server)
    └─────────┘
```

### Running Locally

To run the same tests locally:

```bash
# Start MCP server in background
mix taskweft.mcp &
SERVER_PID=$!

# Wait for startup
sleep 5

# Test 1: List tools
curl -X POST http://localhost:20000/mcp/v1 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  | jq '.result.tools[] | .name' | grep plan

# Test 2: Validate
curl -X POST http://localhost:20000/mcp/v1 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0","id":2,"method":"tools/call","params":{
      "name":"validate",
      "arguments":{"domain_json":"{\"@context\":{\"vsekai\":\"https://v-sekai.org/\",\"domain\":\"vsekai:planning/domain/\"},\"@type\":\"domain:Definition\",\"name\":\"test\",\"variables\":[{\"name\":\"x\",\"type\":\"bool\",\"init\":true}],\"actions\":{\"test\":{\"params\":[],\"body\":[]}},\"methods\":{\"_fallback\":{\"params\":[],\"alternatives\":[]}},\"todo_list\":[[\"test\"]}]"}
    }
  }' | jq

# Cleanup
kill $SERVER_PID
```

### Troubleshooting

If tests fail:

1. Check workflow logs on GitHub Actions
2. Download artifacts: `mcp-server-logs`
3. Review `mix compile` or `mix test` output
4. Verify MCP server starts correctly (`tail -f /tmp/mcp_server.log`)

### Prerequisites

- GitHub repository
- Elixir 1.20+
- OTP 27+

The workflow automatically:
- Caches dependencies (`deps/`, `_build/`)
- Installs Hex and Rebar
- Runs tests in isolation per run
- Cleans up MCP server process

### Results

- **Success**: All tests pass, workflow passes
- **Failure**: Logs uploaded, detailed error messages in GitHub UI