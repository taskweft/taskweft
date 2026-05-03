import Config

# MCP peer configuration. Each entry is `{name, connection_spec}`. Specs
# follow `Taskweft.MCP.Client.connection_spec()` (forwarded to
# `ExMCP.Client.connect/2`).
#
# `minizinc-mcp` peer: provides constraint/optimization solving via the
# system `minizinc` binary (HiGHS / chuffed / cp-sat / gecode bundled).
# Override the path with `TASKWEFT_MINIZINC_MCP_DIR` if your clone is
# elsewhere; unset disables the peer.
peers =
  [
    {:minizinc,
     case System.get_env("TASKWEFT_MINIZINC_MCP_DIR", "/home/ernest.lee/projects/minizinc-mcp") do
       "" ->
         nil

       dir ->
         {
           :stdio,
           # The peer's Application starts an HTTP transport on $PORT
           # (default 8081). We're using stdio, but the HTTP server
           # boots regardless and would conflict if already bound.
           # Letting the OS pick a free port avoids cross-run collisions.
           command: [
             "/home/linuxbrew/.linuxbrew/bin/mix",
             "mcp.server"
           ],
           cd: dir,
           env: [{"PORT", "0"}]
         }
     end}
  ]
  |> Enum.reject(fn {_name, spec} -> is_nil(spec) end)

config :taskweft, :mcp_peers, peers
