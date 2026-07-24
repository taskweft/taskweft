# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule EntityCapabilities do
  use Taskweft.DSL

  @name "entity_capabilities"
  @description "Multi-agent movement domain with heterogeneous entity capabilities. Each entity type can only execute the action matching its capability (fly / swim / walk). The planner filters alternatives via the capabilities section: domain.actions lists required capabilities per action; domain.capabilities.entities lists the capabilities each entity holds. Only alternatives whose required capability is held by the agent are tried. Implements IPyHOP-temporal ReBAC capability filtering (HAS_CAPABILITY relationships). Demonstrates RECTGTN 'E' with action-capability guards."

  @variables %{
    loc: %{type: :int, init: {drone_1: 0, drone_2: 0, boat_1: 2, boat_2: 2, human_1: 0, human_2: 0, amphibious_1: 5}},
    # Current location of each entity. Int keys correspond to location enum values.
  }


  @capabilities %{
    drone_1: ["fly"],
    drone_2: ["fly"],
    boat_1: ["swim"],
    boat_2: ["swim"],
    human_1: ["walk"],
    human_2: ["walk"],
    amphibious_1: ["swim", "walk"],
  }


  @actions %{{
    a_fly: %{
      # Aerial movement. Requires fly capability. Fast — no terrain restrictions.
      params: [:agent, :to_loc],
      duration: "PT5M",
      body: [
        %{eval: %{type: "rebac/check", a: None, b: "None"}}
      ],
    },
  }

  @actions %{{
    a_swim: %{
      # Aquatic movement. Requires swim capability.
      params: [:agent, :to_loc],
      duration: "PT20M",
      body: [
        %{eval: %{type: "rebac/check", a: None, b: "None"}}
      ],
    },
  }

  @actions %{{
    a_walk: %{
      # Ground movement. Requires walk capability. Slowest mode.
      params: [:agent, :to_loc],
      duration: "PT30M",
      body: [
        %{eval: %{type: "rebac/check", a: None, b: "None"}}
      ],
    },
  }


  @methods %{{
    m_move: %{
      params: [:agent, :to_loc],
      alternatives: [
        %{name: "fly"
, subtasks: [
        [""a_fly", "{agent}", "{to_loc}""]
]
        }
        %{name: "swim"
, subtasks: [
        [""a_swim", "{agent}", "{to_loc}""]
]
        }
        %{name: "walk"
, subtasks: [
        [""a_walk", "{agent}", "{to_loc}""]
]
        }
      ],
    },
  }

  @methods %{{
    loc: %{
      params: [:agent, :dest],
      alternatives: [
        %{name: "move_to_dest"
, subtasks: [
        [""m_move", "{agent}", "{dest}""]
]
        }
      ],
    },
  }


  @todo_list [
    [""m_move", "drone_1", {1}"],
]
end