defmodule Mix.Tasks.Taskweft.Mcp do
  @moduledoc """
  Run the Taskweft MCP server.

      mix taskweft.mcp                         # stdio (default)
      mix taskweft.mcp --http                  # Streamable HTTP on 127.0.0.1:51737
      mix taskweft.mcp --http --port 51737     # custom port
      mix taskweft.mcp --http --host 0.0.0.0   # bind all interfaces

  HTTP mode exposes the MCP Streamable HTTP transport: POST any path for
  JSON-RPC requests, GET with `Accept: text/event-stream` (or `/sse`,
  `/mcp/v1/sse`) for the streamed response channel.

  Wire stdio mode into Claude Code by adding to your MCP config:

      {
        "mcpServers": {
          "taskweft": {
            "command": "mix",
            "args": ["taskweft.mcp"],
            "cwd": "/path/to/multiplayer-fabric-taskweft"
          }
        }
      }
  """

  use Mix.Task

  @shortdoc "Run the Taskweft MCP server (stdio or HTTP streaming)"

  @switches [http: :boolean, port: :integer, host: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    if opts[:http] do
      Mix.Task.run("app.start", [])
      start_http(opts)
    else
      ExMCP.Internal.StdioLoggerConfig.configure()
      Mix.Task.run("app.start", [])
      {:ok, _server} = Taskweft.MCP.Server.start_link(transport: :stdio)
      Process.sleep(:infinity)
    end
  end

  defp start_http(opts) do
    port = opts[:port] || 51737
    host = opts[:host] || "127.0.0.1"

    {:ok, _server} =
      Taskweft.MCP.Server.start_link(
        transport: :http,
        port: port,
        host: host,
        sse_enabled: true
      )

    Mix.shell().info("Taskweft MCP listening on http://#{host}:#{port} (Streamable HTTP + SSE)")
    Process.sleep(:infinity)
  end
end
