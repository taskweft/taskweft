defmodule Taskweft.MCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskweft_mcp,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:taskweft_nif, github: "taskweft/nif"},
      {:taskweft_plans, github: "taskweft/plans"},
      {:taskweft_mcp_client, github: "taskweft/mcp-client"},
      {:ex_mcp, "~> 1.0.0-rc", override: true},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test}
    ]
  end
end
