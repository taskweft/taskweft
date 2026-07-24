# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule simple_travel do
  use Taskweft.DSL

  @name "simple_travel"

  @variables %{
    loc: %{type: :int, init: {alice: 0, bob: 1, taxi1: 2, taxi2: 3}},
  }

  @variables %{
    cash: %{type: :float, init: {alice: 20.0, bob: 15.0}},
  }

  @variables %{
    owe: %{type: :float, init: {alice: 0.0, bob: 0.0}},
  }

  @actions %{{
    a_walk: %{
      params: [:person, :to_loc],
      body: [
      ],
    },
  }

  @actions %{{
    a_call_taxi: %{
      params: [:person],
      body: [
      ],
    },
  }

  @actions %{{
    a_ride_taxi: %{
      params: [:person, :to_loc],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/loc/{person}"}, b: "-1"}}
      ],
    },
  }

  @actions %{{
    a_pay_driver: %{
      params: [:person, :to_loc],
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

  @todo_list [
    [""travel", "alice", {2}"],
]
end