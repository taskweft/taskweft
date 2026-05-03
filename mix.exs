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
      {:taskweft_nif, github: "V-Sekai-fire/taskweft-nif"},
      {:taskweft_plans, github: "V-Sekai-fire/taskweft-plans"},
      {:taskweft_mcp_client, github: "V-Sekai-fire/taskweft-mcp-client"},
      {:ex_mcp, "~> 0.9"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test}
    ]
  end
end
