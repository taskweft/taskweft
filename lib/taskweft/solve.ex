defmodule Taskweft.Solve do
  @moduledoc """
  High-level helpers for invoking peer MCP servers configured under
  `:taskweft, :mcp_peers`. `minizinc/2` forwards to the configured
  `:minizinc` peer (e.g. `V-Sekai-fire/minizinc-mcp`) and calls its
  `minizinc_solve` tool.

  ## Configured peers

  Define in `config/runtime.exs`:

      config :taskweft, :mcp_peers, [
        minizinc: {:stdio, command: ["mix", "mcp.server"], cd: "/path/to/minizinc-mcp"}
      ]

  ## Lifecycle

  Each call connects to the peer, invokes the tool, and disconnects.
  Each call pays a ~10ms stdio handshake. For lower latency, hold a
  client via `Taskweft.MCP.Client.connect/1` and reuse it.
  """

  alias Taskweft.MCP.Client

  @doc """
  Solve a MiniZinc model via the configured `:minizinc` peer.

  ## Arguments

    * `model` (binary, required) — `.mzn` model content
    * `opts` (keyword):
      * `:data` — optional `.dzn` data content
      * `:timeout_ms` — solver wall-clock budget (default 30_000)
      * `:peer` — override the peer name (default `:minizinc`)

  ## Returns

    * `{:ok, solution_map}` — peer-provided solution. Shape varies by
      what the peer's `minizinc_solve` tool returns; typically includes
      decoded DZN variables and a solve status.
    * `{:error, reason}` — connection, peer, or solve failure.
  """
  @spec minizinc(binary(), keyword()) :: {:ok, map()} | {:error, any()}
  def minizinc(model, opts \\ []) when is_binary(model) do
    peer = Keyword.get(opts, :peer, :minizinc)

    args =
      %{"model_content" => model}
      |> maybe_put("data_content", Keyword.get(opts, :data))
      |> maybe_put("timeout", Keyword.get(opts, :timeout_ms))

    with_peer(peer, fn client ->
      case Client.call_tool(client, "minizinc_solve", args) do
        {:ok, content} -> {:ok, decode_minizinc_response(content)}
        {:error, _} = err -> err
      end
    end)
  end

  @doc """
  Connect to a configured peer, run `fun` with the client, disconnect.
  """
  @spec with_peer(atom(), (Client.t() -> result)) :: result | {:error, any()}
        when result: any()
  def with_peer(name, fun, opts \\ []) when is_atom(name) and is_function(fun, 1) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    case configured_spec(name) do
      {:ok, spec} ->
        case Client.connect(spec, timeout: timeout) do
          {:ok, client} ->
            try do
              fun.(client)
            after
              Client.disconnect(client)
            end

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp configured_spec(name) do
    case Application.get_env(:taskweft, :mcp_peers, []) |> Keyword.fetch(name) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:peer_not_configured, name}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # `minizinc_solve` returns a single text content block whose `text`
  # field is the JSON-encoded result. Decode it for callers.
  defp decode_minizinc_response([%{"text" => text} | _]) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      _ -> %{"raw" => text}
    end
  end

  defp decode_minizinc_response([%{text: text} | _]) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      _ -> %{"raw" => text}
    end
  end

  defp decode_minizinc_response(other), do: %{"raw" => other}
end
