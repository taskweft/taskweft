defmodule Taskweft.MCP.MixProject do
  use Mix.Project

  @version "0.2.0-dev.15"

  def project do
    [
      app: :taskweft_mcp,
      version: @version,
      elixir: "~> 1.17",
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"],
      description: "MCP server exposing the Taskweft HTN planner over stdio",
      package: package(),
      source_url: "https://github.com/taskweft/mcp"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:taskweft_nif, "~> 0.2.0-dev.3"},
      {:taskweft_plans, "~> 0.2.0-dev"},
      {:taskweft_mcp_client, "~> 0.2.0-dev"},
      {:ex_mcp, "~> 1.0.0-rc"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/taskweft/mcp"}
    ]
  end
end
