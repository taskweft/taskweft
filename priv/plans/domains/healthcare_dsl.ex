# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule healthcare do
  use Taskweft.DSL

  @name "healthcare"

  @variables %{
    room_status: %{type: :int, init: {OR1: 0, OR2: 0, OR3: 4}},
  }

  @variables %{
    room_equipment: %{type: :int, init: {OR1: 0, OR2: 1, OR3: 0}},
  }

  @variables %{
    surgery_complete: %{type: :int, init: {patient1: 0, patient2: 0, patient3: 0}},
  }

  @actions %{{
    a_prepare_room: %{
      params: [:room, :stype],
      body: [
      ],
    },
  }

  @actions %{{
    a_perform_surgery: %{
      params: [:patient, :room, :stype],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/room_status/{room}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_recover_patient: %{
      params: [:patient, :room],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/surgery_complete/{patient}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_clean_room: %{
      params: [:room],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/room_status/{room}"}, b: "0"}}
      ],
    },
  }

  @methods %{{
    schedule_surgery: %{
      params: [:patient, :room, :stype],
      alternatives: [
        %{name: "full_workflow"
, subtasks: [
        [""a_prepare_room", "{room}", "{stype}""]
        [""a_perform_surgery", "{patient}", "{room}", "{stype}""]
        [""a_recover_patient", "{patient}", "{room}""]
        [""a_clean_room", "{room}""]
]
        }
        %{name: "simple_workflow"
, subtasks: [
        [""a_prepare_room", "{room}", "{stype}""]
        [""a_perform_surgery", "{patient}", "{room}", "{stype}""]
        [""a_recover_patient", "{patient}", "{room}""]
]
        }
      ],
    },
  }

  @todo_list [
    [""schedule_surgery", "patient1", "OR1", "cardiac""],
]
end