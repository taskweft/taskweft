# Elixir DSL for RECTGTN Domains

## Overview

The Elixir DSL uses **real Elixir code** with `defmodule`, `use`, and module attributes. No custom DSL keywords — write pure Elixir.

## DSL Syntax

Write a normal Elixir module using module attributes:

```elixir
defmodule BlocksWorld do
  use Taskweft.DSL

  @name "blocks_world"

  @variables %{
    pos: %{type: :ref, init: %{a: "table", b: "hand"}},
    clear: %{type: :bool, init: %{a: true, b: false}}
  }

  @actions %{
    pickup: %{
      params: [:block],
      body: [%{pointer_set: "/pos/{block}", value: "hand"}]
    }
  }

  @todo_list [
    [:move, :a, :table],
    [:move, :b, :table]
  ]
end
```

## Module Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `@name` | string | Domain name |
| `@variables` | map | State variables (`%{name: %{type: ..., init: ...}}`) |
| `@actions` | map | Primitive actions (`%{name: %{params: [...], body: [...]}}`) |
| `@methods` | map | Compound tasks (`%{name: %{params: [...], alternatives: [...]}}`) |
| `@todo_list` | list | Initial tasks (`[[:action, arg, ...], ...]`) |

## I/O

**Input**: Real Elixir module code with module attributes  
**Output**: RECTGTN JSON-LD string

## Example

```elixir
defmodule MyDomain do
  use Taskweft.DSL

  @name "test_domain"

  @variables %{
    pos: %{type: :ref, init: %{a: "table"}}
  }

  @actions %{
    pickup: %{
      params: [:block],
      body: [%{pointer_set: "/pos/{block}", value: "hand"}]
    }
  }

  @todo_list [[:pickup, :a]]
end
```

Compile:

```elixir
iex> domain = """
...> defmodule MyDomain do
...>   use Taskweft.DSL
...>   @name "test"
...>   @todo_list [[:test, :a]]
...> end
...> """
iex> Taskweft.DSL.compile(domain)
{:ok, "{\"@context\":...}
```

## Why Real Elixir?

- Valid Elixir code — compiles with `mix compile`
- IDE autocomplete and type checking
- No custom DSL keywords
- AST-safe parsing (no code execution)
- ~60% fewer tokens than JSON-LD