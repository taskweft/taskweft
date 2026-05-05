defmodule Taskweft.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: [propcheck: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # NIF-free V-Sekai deps — taskweft_nif, taskweft_rebac, and taskweft_mcp
      # have been replaced by pure Elixir implementations in lib/taskweft/ so
      # this project compiles under AtomVM/Popcorn (no C NIFs, no exqlite, no jaxon).
      {:taskweft_mcp_client, github: "V-Sekai-fire/taskweft-mcp-client"},

      # Supabase Postgres — replaces exqlite/SQLite.
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},

      # Pure Elixir JSON — AtomVM-compatible.
      {:jason, "~> 1.4"},

      # Dev / test
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:timex, "~> 3.7", only: :test}

      # Popcorn (Elixir -> AtomVM WASM) requires OTP 26.0.2 + Elixir 1.17.3 exactly.
      # Switch with `asdf install` / `mise use`, then add:
      # {:popcorn, "~> 0.2", only: :dev, runtime: false}
    ]
  end
end
