# Taskweft DSL Migration

This PR replaces JSON-LD input with Elixir DSL for domain definitions.

## Changes

### New Files

1. **lib/taskweft/dsl.ex** - Struct-based DSL compilation
   - Compiles Elixir structs to JSON-LD for the RECTGTN planner
   - Supports full domain definition syntax

2. **lib/taskweft/domain/safe_parser.ex** - Elixir DSL parser
   - Parses Elixir DSL strings to JSON-LD
   - Based on commit c6b5830
   - AST-safe (no runtime code execution)

3. **test/integration/curl/** - Curl-based integration tests
   - `blocks_world_dsl.ex` - Example Elixir DSL domain
   - `test_integration.sh` - Test script for MCP endpoints
   - `dsl_compiler.ex` - Simple compiler script

### Modified Files

1. **lib/taskweft/mcp/server.ex**
   - Added `plan_dsl` tool - accepts DSL input
   - Added `alias Taskweft.DSL` and `alias Taskweft.MCP.Plans`
   - Updated tool description table

## Usage

### Option 1: Struct-based DSL

```elixir
alias Taskweft.DSL

domain = %DSL.Domain{
  name: "blocks_world",
  variables: [
    %DSL.Variable{name: "pos", type: "ref", init: %{a: "b", b: "table", c: "table"}},
    %DSL.Variable{name: "clear", type: "bool", init: %{a: true, b: false, c: true}}
  ],
  actions: %{
    a_pickup: %DSL.Action{
      params: ["block"],
      body: [
        %DSL.Eval{type: "math/eq", a: %DSL.PointerGet{pointer: "/pos/{block}"}, b: "table"},
        %DSL.PointerSet{pointer: "/pos/{block}", value: "hand"}
      ]
    }
  },
  todo_list: [["a_pickup", "a"]]
}

{:ok, json} = DSL.compile(domain)
{:ok, plan} = Taskweft.plan(json)
```

### Option 2: String-based DSL

```elixir
dsl = '''
name "blocks_world"
variable :pos, type: :ref, init: %{a: "b", b: "table"}
action :a_pickup, params: [:block], body: [
  condition(:math/eq, pointer_get("/pos/{block}"), "table"),
  pointer_set("/pos/{block}", "hand")
]
todo_list [[":a_pickup", "a"]]
'''

{:ok, json} = Taskweft.Domain.SafeParser.parse(dsl)
{:ok, plan} = Taskweft.plan(json)
```

### Option 3: MCP plan_dsl tool

```bash
curl -X POST http://localhost:20000/mcp/v1 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "plan_dsl",
      "arguments": {
        "domain_dsl": {
          "name": "blocks_world",
          "variables": [...],
          "actions": {...},
          "todo_list": [...]
        }
      }
    }
  }'
```

## Integration Tests

Run the curl-based integration test:

```bash
./test/integration/curl/test_integration.sh [dsl_file]
```

## Testing

```bash
# Compile the project
mix compile

# Run unit tests
mix test

# Run property tests
mix test --include property
```

## Rationale

The DSL approach:
1. Type-safe Elixir code vs JSON strings
2. Better IDE support and autocomplete
3. Error messages are clearer
4. No escaping/quotations issues
5. Follows the successful pattern from commit c6b5830