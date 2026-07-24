# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule temporal_travel do
  use Taskweft.DSL

  @name "temporal_travel"
  @description "Travel planning domain with temporal action durations (ISO 8601). Agents can walk directly or use a taxi: call, ride, then pay. Demonstrates multi-step sequential task decomposition (RECTGTN 'T') and temporal metadata — each action carries a 'duration' field usable by a Simple Temporal Network (STN) to check schedule feasibility. Duration values follow ISO 8601 (PT = period-time prefix: PTxH = hours, PTxM = minutes)."

  @variables %{
    loc: %{type: :int, init: {alice: 0, bob: 1, taxi1: 2, taxi2: 3}},
    # Current location of each agent and taxi. -1 means in transit (taxi called, not yet arrived).
  }

  @variables %{
    cash: %{type: :float, init: {alice: 20.0, bob: 15.0}},
    # Cash on hand per agent (float, currency units).
  }

  @variables %{
    owe: %{type: :float, init: {alice: 0.0, bob: 0.0}},
    # Amount owed to taxi driver per agent (accumulated during ride).
  }

  @actions %{{
    a_walk: %{
      # Walk directly to destination. No cost, but takes longer than taxi.
      params: [:person, :to_loc],
      duration: "PT10M",
      body: [
      ],
    },
  }

  @actions %{{
    a_call_taxi: %{
      # Hail taxi1 to current location; person enters transit state (loc = -1).
      params: [:person],
      duration: "PT2M",
      body: [
      ],
    },
  }

  @actions %{{
    a_ride_taxi: %{
      # Ride taxi1 to destination. Person must be in transit (loc == -1). Fare = 1.5 + 0.5 * 8 (fixed route cost).
      params: [:person, :to_loc],
      duration: "PT15M",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/loc/{person}"}, b: "-1"}}
      ],
    },
  }

  @actions %{{
    a_pay_driver: %{
      # Pay accumulated fare and exit taxi at destination. Requires sufficient cash.
      params: [:person, :to_loc],
      duration: "PT1M",
      body: [
        %{eval: %{type: "math/ge", a: %{pointer: "/cash/{person}"}, b: "{owed}"}}
      ],
    },
  }

  @methods %{{
    travel: %{
      params: [:person, :dest],
      alternatives: [
        %{name: "already_there"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/loc/{person}"}, b: "{dest}"}}
],
        }
        %{name: "by_foot"
, subtasks: [
        [""a_walk", "{person}", "{dest}""]
]
        }
        %{name: "by_taxi"
, subtasks: [
        [""a_call_taxi", "{person}""]
        [""a_ride_taxi", "{person}", "{dest}""]
        [""a_pay_driver", "{person}", "{dest}""]
]
        }
      ],
    },
  }

  @methods %{{
    loc: %{
      params: [:person, :dest],
      alternatives: [
        %{name: "travel_to_dest"
, subtasks: [
        [""travel", "{person}", "{dest}""]
]
        }
      ],
    },
  }

  @todo_list [
    [""travel", "alice", {2}"],
]
end