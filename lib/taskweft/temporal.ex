defmodule Taskweft.Temporal do
  @moduledoc """
  Pure Elixir temporal scheduler / checker.

  Implements `check_temporal` and `check_temporal_civil` matching the
  C++ NIF's JSON output, including the `"total"` field consumed by the
  cross-check tests in `iso8601_duration_prop_test.exs`.

  Output envelope:

      {
        "plan":     [["action", ...], ...],
        "schedule": [{"step": 0, "action": "...", "start": "PT0S",
                      "duration": "PT1S", "end": "PT1S"}],
        "feasible": true,
        "total":    "PT1S",
        "origin":   "PT0S"
      }
  """

  alias Taskweft.Iso8601Duration
  alias Taskweft.Planner

  # ── Public API ────────────────────────────────────────────────────────────

  def plan_with_temporal(domain_json, origin_iso) do
    domain = Jason.decode!(domain_json)
    plan = extract_plan!(domain)
    check_temporal_impl(domain, plan, origin_iso, nil)
  end

  def plan_with_temporal_civil(domain_json, origin_iso, reference_date) do
    domain = Jason.decode!(domain_json)
    plan = extract_plan!(domain)
    check_temporal_impl(domain, plan, origin_iso, reference_date)
  end

  def check_temporal(domain_json, plan_json, origin_iso) do
    domain = Jason.decode!(domain_json)
    plan = Jason.decode!(plan_json)
    check_temporal_impl(domain, plan, origin_iso, nil)
  end

  def check_temporal_civil(domain_json, plan_json, origin_iso, reference_date) do
    domain = Jason.decode!(domain_json)
    plan = Jason.decode!(plan_json)
    check_temporal_impl(domain, plan, origin_iso, reference_date)
  end

  # ── Core implementation ───────────────────────────────────────────────────

  defp extract_plan!(domain) do
    case Planner.run(domain) do
      {:ok, plan} -> plan
      {:error, reason} -> raise reason
    end
  end

  defp check_temporal_impl(domain, plan, origin_iso, reference_date) do
    actions = domain["actions"] || %{}
    origin_ms = parse_ms!(origin_iso)
    ref_date = parse_ref_date(reference_date)

    {schedule, _current_ms, total_ms} =
      Enum.reduce(plan, {[], origin_ms, 0}, fn [action | _], {sched, current_ms, accum} ->
        spec = actions[action] || %{}
        dur_str = spec["duration"] || "PT0S"
        dur_ms = duration_ms(dur_str, ref_date)

        step = %{
          "step" => length(sched),
          "action" => action,
          "start" => ms_to_iso(current_ms),
          "duration" => dur_str,
          "end" => ms_to_iso(current_ms + dur_ms)
        }

        {[step | sched], current_ms + dur_ms, accum + dur_ms}
      end)

    Jason.encode!(%{
      "plan" => plan,
      "schedule" => Enum.reverse(schedule),
      "feasible" => true,
      "total" => ms_to_iso(total_ms),
      "origin" => origin_iso
    })
  end

  # ── Duration → milliseconds ───────────────────────────────────────────────

  defp duration_ms(iso, nil) do
    case Iso8601Duration.parse(iso) do
      {:ok, comps} -> Iso8601Duration.total_milliseconds(comps)
      {:error, _} -> 0
    end
  end

  defp duration_ms(iso, ref_date) do
    case Iso8601Duration.parse(iso) do
      {:ok, comps} -> civil_ms(comps, ref_date)
      {:error, _} -> 0
    end
  end

  defp civil_ms(components, ref_date) do
    {total_ms, _} =
      Enum.reduce(components, {0, ref_date}, fn comp, {acc_ms, date} ->
        {ms, next_date} = civil_component_ms(comp, date)
        {acc_ms + ms, next_date}
      end)

    total_ms
  end

  defp civil_component_ms(%{unit: :y, whole: n, frac_milli: 0}, date) when not is_nil(date) do
    try do
      end_date = shift_years(date, n)
      days = Date.diff(end_date, date)
      {days * 86_400_000, end_date}
    rescue
      _ -> {n * 365 * 86_400_000, date}
    end
  end

  defp civil_component_ms(%{unit: :mo, whole: n, frac_milli: 0}, date) when not is_nil(date) do
    try do
      end_date = shift_months(date, n)
      days = Date.diff(end_date, date)
      {days * 86_400_000, end_date}
    rescue
      _ -> {n * 30 * 86_400_000, date}
    end
  end

  defp civil_component_ms(comp, date) do
    ms = Iso8601Duration.total_milliseconds([comp])
    {ms, date}
  end

  defp shift_years(date, n) do
    new_year = date.year + n
    days_in_month = Date.days_in_month(Date.new!(new_year, date.month, 1))
    day = min(date.day, days_in_month)
    Date.new!(new_year, date.month, day)
  end

  defp shift_months(date, n) do
    total_months = date.month - 1 + n
    new_year = date.year + div(total_months, 12)
    new_month = rem(total_months, 12) + 1
    days_in_month = Date.days_in_month(Date.new!(new_year, new_month, 1))
    day = min(date.day, days_in_month)
    Date.new!(new_year, new_month, day)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp parse_ms!(iso) do
    case Iso8601Duration.parse(iso) do
      {:ok, comps} -> Iso8601Duration.total_milliseconds(comps)
      {:error, _} -> 0
    end
  end

  defp parse_ref_date(nil), do: nil
  defp parse_ref_date(""), do: nil

  defp parse_ref_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  @doc "Convert milliseconds back to an ISO 8601 duration string."
  def ms_to_iso(0), do: "PT0S"

  def ms_to_iso(ms) when is_integer(ms) and ms > 0 do
    total_s = div(ms, 1000)
    days = div(total_s, 86_400)
    remaining_s = rem(total_s, 86_400)

    cond do
      days > 0 and remaining_s > 0 -> "P#{days}DT#{remaining_s}S"
      days > 0 -> "P#{days}D"
      remaining_s > 0 -> "PT#{remaining_s}S"
      true -> "PT0S"
    end
  end

  def ms_to_iso(_), do: "PT0S"
end
