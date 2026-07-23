# Elixir DSL for RECTGTN Domains

## Overview

The Elixir DSL provides a human-readable, Elixir-like syntax for defining RECTGTN HTN domains. It compiles to an AST and is parsed safely without code execution, making it ideal for LLM ingestion while providing IDE autocomplete and type checking.

## DSL Syntax

### Domain Declaration

```elixir
name "domain_name"
```

### State Variables

Define per-entity state variables with optional initial values:

```elixir
variable :pos, type: :ref, init: %{a: "table", b: "hand"}
variable :clear, type: :bool, init: %{a: true, b: false}
variable :holding, type: :bool, init: %{hand: false}
```

**Types**: `:bool`, `:int`, `:float`, `:ref`, `:float2`, `:float3`, `:float4`, `:float2x2`, `:float3x3`, `:float4x4`

### Primitive Actions

```elixir
action :pickup,
  params: [:block],
  body: [
    condition(:math/eq, pointer_get("/pos/{block}"), "table"),
    pointer_set("/pos/{block}", "hand"),
    pointer_set("/holding/hand", "{block}")
  ]
```

**Duration**: Optional temporal specification

```elixir
action :fly,
  params: [:agent, :to],
  duration: "PT5M",
  body: [pointer_set("/loc/{agent}", "{to}")]
```

### Methods (Compound Tasks)

Decompose tasks via alternatives:

```elixir
method :move,
  params: [:block, :dest],
  alternatives: [
    alt(:get_and_put,
      subtasks: [
        [:get, "{block}"],
        [:put, "{block}", "{dest}"]
      ]
    )
  ]
```

### Guards

Optional preconditions:

```elixir
action :pickup,
  params: [:block],
  body: [
    condition(:math/eq, pointer_get("/pos/{block}"), "table"),
    condition(:math/eq, pointer_get("/clear/{block}"), true),
    pointer_set("/pos/{block}", "hand")
  ]
```

### Capabilities (ReBAC)

Entity capabilities and relationships:

```elixir
capabilities %{
  entities: %{drone: [:fly], human: [:walk]},
  graph: [
    %{subject: "alice", rel: "HAS_CAPABILITY", object: "fly"},
    %{subject: "alice", rel: "IS_MEMBER_OF", object: "flight_team"}
  ]
}
```

**Relations**: `HAS_CAPABILITY`, `CONTROLS`, `OWNS`, `IS_MEMBER_OF`, `DELEGATED_TO`, `SUPERVISOR_OF`, `PARTNER_OF`, `CAN_ENTER`, `CAN_INSTANCE`

### Todo List

Specify initial tasks:

```elixir
todo_list [
  [:move, :a, :table],
  [:move, :b, :table],
  %{goal: [%{pointer: "/switch/x", eq: true}]},
  %{multigoal: %{switch: %{x: true, y: true}}}
]
```

**Task kinds**:
- **TwCall**: `[action_name, arg, ...]`
- **TwGoal**: `%{goal: [%{pointer: "/var/key", eq: value}]}`
- **TwMultiGoal**: `%{multigoal: %{var: %{key: value}}}`

## Usage

### Parse DSL String

```elixir
iex> domain = "
...>   name \"blocks_world\"
...>   variable :pos, type: :ref, init: %{a: \"table\", b: \"table\"}
...>   action :pickup, params: [:block], body: [pointer_set(\"/pos/{block}\", \"hand\")]
...>   todo_list [[:pickup, :a]]
...> "
iex> Taskweft.DSL.parse(domain)
{:ok, "{\"@context\":...,...}"}
```

### Use Builder Macro

```elixir
defmodule MyDomain do
  use Taskweft.DSL.Builder

  name "my_domain"

  variable :pos, type: :ref, init: %{a: "table"}
  action :pickup, params: [:block], body: [pointer_set("/pos/{block}", "hand")]

  def compile do
    domain = __MODULE__.__domain_definition__()
    Taskweft.DSL.SafeParser.parse(domain)
  end
end
```

## Why DSL?

- **60% fewer tokens** than JSON-LD
- **AST-safe** parsing (no code execution)
- **IDE autocomplete** and syntax highlighting
- **Type safety** through Elixir's compile-time checks

## Examples

### Blocks World

```elixir
name "blocks_world"

variable :pos, type: :ref, init: %{a: "table", b: "table"}
variable :clear, type: :bool, init: %{a: true, b: true}

action :pickup,
  params: [:block],
  body: [
    condition(:math/eq, pointer_get("/pos/{block}"), "table"),
    condition(:math/eq, pointer_get("/clear/{block}"), true),
    pointer_set("/pos/{block}", "hand"),
    pointer_set("/clear/{block}", false),
    pointer_set("/holding/hand", "{block}")
  ]

method :move_one,
  params: [:block, :dest],
  alternatives: [
    alt(:get_and_put,
      subtasks: [
        [:get, "{block}"],
        [:put, "{block}", "{dest}"]
      ]
    )
  ]

todo_list [[:move_one, :a, :table], [:move_one, :b, :table]]
```

### Multi-Agent with ReBAC

```elixir
variable :loc, type: :ref, init: %{drone: "base", human: "base"}

action :fly,
  params: [:agent, :to],
  duration: "PT5M",
  body: [
    rebac_check("{agent}", "HAS_CAPABILITY", "fly"),
    pointer_set("/loc/{agent}", "{to}")
  ]

method :m_move,
  params: [:agent, :to],
  alternatives: [
    alt(:fly, subtasks: [[:a_fly, "{agent}", "{to}"]]),
    alt(:walk, subtasks: [[:a_walk, "{agent}", "{to}"]])
  ]

capabilities %{
  entities: %{drone: [:fly], human: [:walk], amphibious: [:swim, :walk]}
}

todo_list [[:m_move, :drone, :city]]
```

## Comparison

| Format | Token Count | Parse Safety | IDE Support |
|--------|-------------|--------------|-------------|
| JSON-LD | 100% | ❌ NIF only | ❌ No |
| YAML-LD | 40% | ⚠️ YAML parser | ⚠️ Limited |
| **Elixir DSL** | **~60%** | **✅ AST-safe** | **✅ Full** |

## See Also

- [REST API Docs](https://github.com/taskweft/taskweft/blob/main/docs/rectgtn.md)
- [SAFE PARSER](./safe_parser.md)
- [BUILDER](./builder.md)