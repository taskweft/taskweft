defmodule Taskweft.Edge do
  @moduledoc """
  AtomVM entry point for the Supabase Edge Function.

  Called by Popcorn's boot module as `Taskweft.Edge.start/0`.  Registers
  with the AtomVM emscripten C layer by calling `run_script_tracked`
  (which avoids the browser-specific `window.parent` wrapper that
  `Popcorn.Wasm.register/1` adds) and then loops on incoming JS calls.

  Message protocol (AtomVM `:emscripten` module):
    - Incoming call: `{:emscripten, {:call, promise, json_binary}}`
    - Reply:         `:emscripten.promise_resolve(promise, json_binary)`
    - Error:         `:emscripten.promise_reject(promise, json_binary)`
  """

  @doc "Entry point called by Popcorn's boot module."
  def start() do
    # Register this process under its module atom so that the C `call` NIF can
    # route JS Module.call("Elixir.Taskweft.Edge", args) to this mailbox.
    Process.register(self(), __MODULE__)

    # Trigger onElixirReady via :emscripten.run_script_tracked so the JS side
    # knows AtomVM is ready.  We call the C NIF directly (bypassing
    # Popcorn.Wasm.register which uses window.parent — not in Deno).
    :emscripten.run_script_tracked("""
    (Module) => {
      if (typeof Module.onElixirReady === "function") {
        Module.onElixirReady("Elixir.Taskweft.Edge");
      }
      return [];
    }
    """)

    loop()
  end

  defp loop() do
    receive do
      {:emscripten, {:call, promise, raw}} ->
        result =
          case Jason.decode(raw) do
            {:ok, body} -> handle(body)
            {:error, _} -> %{"error" => "invalid json"}
          end

        case Jason.encode(result) do
          {:ok, json} -> :emscripten.promise_resolve(promise, json)
          {:error, _} -> :emscripten.promise_reject(promise, ~s({"error":"encode failed"}))
        end

        loop()

      {:emscripten, {:cast, _raw}} ->
        loop()

      _other ->
        loop()
    end
  end

  defp handle(%{"action" => "ping"}) do
    %{"status" => "ok", "runtime" => "atomvm-wasm"}
  end

  defp handle(%{"action" => "plan", "tasks" => tasks}) do
    ordered = Enum.sort_by(tasks, & &1["priority"], :desc)
    %{"status" => "ok", "plan" => ordered}
  end

  defp handle(_unknown) do
    %{"status" => "error", "reason" => "unknown action"}
  end
end
