# Taskweft DSL Implementation

## Summary

This PR adds Elixir DSL support for RECTGTN domain definitions, replacing direct JSON-LD string input with more convenient DSL syntax.

## Changes

### New Files

1. **lib/taskweft/dsl.ex** (3.5 KB)
   - Struct-based DSL compiler
   - Compiles Elixir structs to JSON-LD

2. **lib/taskweft/domain/safe_parser.ex** (7.4 KB)
   - Elixir DSL string parser
   - AST-safe, based on commit c6b5830

3. **test/integration/** (7 KB)
   - `blocks_world_dsl.ex` - Example Elixir DSL domain
   - `test_integration.sh` - Shell-based integration test
   - `dsl_compiler.ex` - Simple compiler utility

4. **.github/workflows/integration-test.yml** (3.6 KB)
   - GitHub Actions workflow for CI
   - Runs unit, property, and MCP integration tests via curl
   - Logs saved on failure

### Modified Files

1. **lib/taskweft/mcp/server.ex** (+37 lines)
   - Added `plan_dsl` tool
   - Added DSL support to existing tools
   - Maintains backwards compatibility with JSON-LD

## DSL Syntax

### Struct-based (new)
```elixir
alias Taskweft.DSL

domain = %DSL.Domain{
  name: "blocks_world",
  variables: [%DSL.Variable{name: "pos", type: "ref", init: %{a: "b"}}],
  todo_list: [["a_pickup", "a"]]
}
{:ok, json} = DSL.compile(domain)
```

### String-based (new)
```elixir
dsl = '''
name "blocks_world"
variable :pos, type: :ref, init: %{a: "b"}
action :a_pickup, params: [:block], body: [
  condition(:math/eq, pointer_get("/pos/{block}"), "table"),
  pointer_set("/pos/{block}", "hand")
]
todo_list [[":a_pickup", "a"]]
'''
{:ok, json} = Taskweft.Domain.SafeParser.parse(dsl)
```

### MCP Tool (new)
```bash
curl -X POST http://localhost:20000/mcp/v1 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "plan_dsl",
      "arguments": {"domain_dsl": {...}}
    }
  }'
```

## Testing

### GitHub Actions
```bash
# On push or PR, CI automatically runs:
mix test                    # Unit tests
mix test --include property # Property tests
# MCP integration tests via curl
```

### Locally
```bash
# Run tests
mix test && mix test --include property

# Run MCP integration test
./test/integration/curl/test_integration.sh

# Start server manually
mix taskweft.mcp
```

## Benefits

1. **Type Safety** - Elixir compile-time checks vs string escaping
2. **IDE Support** - Autocomplete, refactoring, error highlighting
3. **Readability** - Clear intent over verbose JSON-LD
4. **Safety** - AST-safe parsing, no runtime code execution
5. **Backwards Compatible** - JSON-LD still supported via plan tool

## Comparison

| Aspect | JSON-LD | DSL |
|--------|---------|-----|
| Error Detection | Runtime | Compile-time |
| IDE Support | Basic | Full |
| Readability | Verbose | Clear |
| Tooling | Manual | Built-in |
| Safety | Runtime | Compile-time |

## Checklist

- [x] Created DSL compilation module
- [x] Created SafeParser from git history
- [x] Updated MCP server with plan_dsl tool
- [x] Added GitHub Actions workflow
- [x] Created integration test files
- [x] Added documentation
- [x] Maintained backwards compatibility