# DSL Migration Guide

This migration guides users from JSON-LD input to a domain-specific language (DSL) for building RECTGTN HTN domains.

## Why DSL?

The DSL provides a more idiomatic Elixir interface for defining domains:

- **Type safety**: Struct definitions with TypedStruct
- **Easier syntax**: Elixir code instead of JSON-LD nesting
- **Better tooling**: IDE autocomplete and error detection
- **Cleaner error messages**: Elixir exception details

## Basic Example

### Before (JSON-LD)

```json
{
  "@context": {"vsekai": "https://v-sekai.org/"},
  "@type": "domain:Definition",
  "name": "move-domain",
  "variables": [
    {"name": "loc", "type": "ref", "init": "base"}
  ],
  "actions": {
    "move": {
      "params": ["agent"],
      "body": [
        {"type": "pointer/set", "pointer": "loc", "value": "city"}
      ]
    }
  },
  "todo_list": [["move"]]
}
```

### After (DSL)

```elixir
defmodule MyDomain do
  use Taskweft.DSL

  def compile() do
    domain = %__MODULE__{
      name: "move-domain",
      variables: [%DSL.Variable{name: "loc", type: "ref", init: "base"}],
      actions: %{
        move: %DSL.Action{
          params: ["agent"],
          body: [
            %DSL.PointerSet{pointer: "loc", value: "city"}
          ]
        }
      },
      todo_list: [["move"]]
    }

    Taskweft.DSL.compile(domain)
  end
end
```

## Full Example: Blocks World

See `test/integration/curl/blocks_world_dsl.ex` for a complete blocks world domain.

## Migrating Existing Domains

1. Keep your JSON-LD in `lib/taskweft/domain/*.json`
2. Create DSL equivalents in `lib/taskweft/domain/*.ex`
3. Use `Taskweft.MCP.Server.compile/1` in your code
4. Update tests to use curl instead of Elixir

## Running Tests

```bash
# Unit tests
mix test

# Integration tests (curl)
bash test/integration/curl/test_integration.sh

# CI tests
mix compile --warnings-as-errors
```

## Troubleshooting

### Compilation Errors

- Ensure `typed_struct` dependency is installed: `mix deps.get`
- Check field types match definitions
- Verify struct nesting uses `__MODULE__` references

### Runtime Errors

- JSON-LD output should match RECTGTN spec
- Verify `@context` and `@type` fields are correct
- Check `capabilities` are included in output