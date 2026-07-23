# DSL Technical Summary

## Architecture

The Elixir DSL wraps the RECTGTN HTN planner using TypedStruct for type safety.

### Components

1. **`Taskweft.DSL`** - Main module with compile/1 function
2. **`DSL.Variable`** - Variable definition
3. **`DSL.Action`** - Action definition with body steps
4. **`DSL.Method`** - Method with alternatives
5. **`DSL.Alternative`** - Alternative in method
6. **`DSL.Eval`** - Evaluation step
7. **`DSL.PointerSet`** - Pointer set operation

### Data Flow

```
DSL struct → Taskweft.DSL.compile/1
    ↓
build_json_domain/1
    ↓
JSON-LD → RECTGTN planner
```

## Compilation Pipeline

1. **Input**: TypedStruct domain
2. **Validation**: TypedStruct enforces field types
3. **Transformation**: build_json_domain/1 converts to JSON-LD
4. **Output**: JSON string with RECTGTN spec

## Type Safety

Uses `TypedStruct` for compile-time type checking:

```elixir
use TypedStruct

typedstruct do
  field :name, String.t()
  field :variables, [__MODULE__.Variable]
  field :actions, %{String.t() => __MODULE__.Action}
end
```

## Error Handling

```elixir
def compile(%__MODULE__{} = domain) do
  json = Jason.encode!(build_json_domain(domain))
  {:ok, json}
end
```

- **Compilation errors**: Caught at compile time by TypedStruct
- **Encoding errors**: Wrapped in `{:error, reason}`
- **Runtime validation**: Struct patterns handle all cases

## Performance Considerations

1. **Serialization**: Jason.encode!/1 is fast for domains < 1MB
2. **Struct matching**: Pattern matching on structs is O(1) per field
3. **List comprehensions**: Enum.map is optimized for small lists

## Limitations

- No duration support in DSL (add if needed)
- No method-specific guards (add if needed)
- No JSON-LD input validation (safe_parser.ex provides basic support)

## Future Enhancements

1. Add duration support to DSL
2. Add method-level preconditions
3. Add domain-level guards
4. Add DSL validator with custom checks
5. Add DSL to JSON-LD round-trip testing