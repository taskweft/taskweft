defmodule Taskweft.MCP.Client do
  @moduledoc """
  MCP client wrapper around `ExMCP.Client`. Connects to peer MCP servers,
  lists their tools, and invokes them by name.

  ## Connection specs

  Mirrors `ExMCP.Client.connect/2`:

  * `"https://example.com/mcp"` — HTTP transport
  * `"stdio:/path/to/binary"` — stdio with the given executable
  * `{:stdio, command: "mix", args: ["mcp.server"]}` — explicit stdio
  * `{:http, url: "https://..."}` — explicit HTTP
  * a list of the above — multi-transport client

  ## Usage

      {:ok, client} = Taskweft.MCP.Client.connect({:stdio,
        command: "/usr/bin/env",
        args: ["bash", "-c", "cd /path/to/minizinc-mcp && exec mix mcp.server"]
      })

      {:ok, %{"tools" => tools}} = Taskweft.MCP.Client.list_tools(client)

      {:ok, result} = Taskweft.MCP.Client.call_tool(client,
        "minizinc_solve",
        %{"model_content" => "var 0..9: x;\\nsolve satisfy;"}
      )

      Taskweft.MCP.Client.disconnect(client)

  ## Configured peers

  Connections can also be declared via `Application.put_env(:taskweft,
  :mcp_peers, [...])` and started with `connect_configured/0`.
  """

  alias ExMCP.Client

  @typedoc "Same shape as ExMCP.Client.connection_spec()"
  @type connection_spec ::
          String.t()
          | {atom(), keyword()}
          | [String.t() | {atom(), keyword()}]

  @typedoc "Started client process (GenServer)"
  @type t :: GenServer.server()

  @doc """
  Connect to a single peer MCP server. Returns `{:ok, client}` on success.

  ## Options

    * `:name` — register the GenServer under a name
    * `:timeout` — connection timeout (default 5_000 ms)
    * additional options forwarded to `ExMCP.Client.start_link/1`
  """
  @spec connect(connection_spec(), keyword()) :: {:ok, t()} | {:error, any()}
  def connect(spec, opts \\ []) do
    # ExMCP.Client.connect uses GenServer.start_link, which signals exits
    # on transport failure. Catch and convert to {:error, _} so callers
    # don't have to trap exits.
    try do
      Client.connect(spec, opts)
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @doc """
  Disconnect a previously-connected peer.
  """
  @spec disconnect(t()) :: :ok
  def disconnect(client) do
    GenServer.stop(client, :normal, 5_000)
    :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  List the tools the peer exposes. Returns the unwrapped list of tool
  metadata maps (the `tools` field of the underlying `ExMCP.Response`).
  """
  @spec list_tools(t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_tools(client, opts \\ []) do
    case Client.list_tools(client, opts) do
      {:ok, %ExMCP.Response{tools: tools}} when is_list(tools) -> {:ok, tools}
      {:ok, %{"tools" => tools}} when is_list(tools) -> {:ok, tools}
      {:ok, other} -> {:error, {:unexpected_list_tools_shape, other}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Call a tool on the peer by name. `arguments` is a map of JSON-shaped
  parameters per the tool's input_schema.

  Returns `{:ok, content_blocks}` where `content_blocks` is the list of
  MCP content items (each typically `%{"type" => "text", "text" => ...}`).
  Errors from the underlying peer are surfaced as `{:error, reason}`.
  """
  @spec call_tool(t(), String.t(), map(), keyword()) ::
          {:ok, [map()]} | {:error, any()}
  def call_tool(client, tool_name, arguments, opts \\ []) do
    case Client.call_tool(client, tool_name, arguments, opts) do
      {:ok, %ExMCP.Response{is_error: true} = resp} ->
        {:error, {:tool_error, resp.content}}

      {:ok, %ExMCP.Response{content: content}} ->
        {:ok, content}

      {:ok, %{"content" => content}} ->
        {:ok, content}

      {:ok, other} ->
        {:error, {:unexpected_call_tool_shape, other}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Connect to all peers declared in `Application.get_env(:taskweft,
  :mcp_peers)`. Returns a map `name => {:ok, client} | {:error, reason}`.

  Each peer entry is `{name :: atom(), spec :: connection_spec()}`.
  """
  @spec connect_configured() :: %{atom() => {:ok, t()} | {:error, any()}}
  def connect_configured do
    peers = Application.get_env(:taskweft, :mcp_peers, [])

    Map.new(peers, fn {name, spec} ->
      {name, connect(spec)}
    end)
  end
end
