defmodule Taskweft.Edge do
  @moduledoc """
  Minimal entry point for Popcorn/AtomVM compilation targeting Supabase Edge Functions.

  Intentionally avoids any NIF-dependent modules (taskweft_nif, exqlite, jaxon)
  since AtomVM does not support Erlang NIFs.
  """

  def main do
    receive do
      {:request, from, body} ->
        response = handle(body)
        send(from, {:response, response})
        main()
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
