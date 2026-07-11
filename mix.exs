defmodule Taskweft.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :taskweft,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: [propcheck: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Taskweft.Application, []}
    ]
  end

  # Standalone Burrito binary — see issue #53 and `Taskweft.CLI`.
  #
  # The `Taskweft.Release.wrap/1` step only invokes Burrito when a zig
  # toolchain is present (or `TASKWEFT_BURRITO=1` forces it), so a plain
  # `mix release taskweft` still assembles on a machine without zig; CI
  # builds the per-triplet binaries with the toolchain installed.
  defp releases do
    [
      taskweft: [
        version: @version,
        steps: [:assemble, &Taskweft.Release.wrap/1],
        burrito: [
          targets: [
            # Burrito bundles a musl ERTS on Linux but recompiles the NIF for
            # `x86_64-linux` (glibc), so the .so fails to load (the module then
            # reports "not available"). Force the NIF to target musl too — zig
            # takes the last `-target`, overriding Burrito's default.
            linux_amd64: [
              os: :linux,
              cpu: :x86_64,
              nif_cflags: "-target x86_64-linux-musl",
              nif_cxxflags: "-target x86_64-linux-musl"
            ],
            linux_arm64: [
              os: :linux,
              cpu: :aarch64,
              nif_cflags: "-target aarch64-linux-musl",
              nif_cxxflags: "-target aarch64-linux-musl"
            ],
            macos_arm64: [os: :darwin, cpu: :aarch64],
            windows_amd64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp deps do
    [
      {:taskweft_nif, github: "V-Sekai-fire/taskweft-nif"},
      {:taskweft_rebac, github: "V-Sekai-fire/taskweft-rebac"},
      {:taskweft_mcp_client, github: "V-Sekai-fire/taskweft-mcp-client"},
      {:taskweft_mcp, github: "V-Sekai-fire/taskweft-mcp"},
      {:burrito, "~> 1.5"},
      {:json_ld, "~> 1.0"},
      {:rdf, "~> 3.0"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:timex, "~> 3.7", only: :test}
    ]
  end
end
