# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule robosub do
  use Taskweft.DSL

  @name "robosub"

  @variables %{
    loc: %{type: :ref, init: {robot: l0}},
  }

  @variables %{
    found: %{type: :int, init: {l0: 1, l1: 0, l2: 0, l3: 0, l4: 0, l5: 0, g: 0, v1: 0, v2: 0}},
  }

  @variables %{
    crossed_gate: %{type: :int, init: {g: 0}},
  }

  @variables %{
    vampire_touched: %{type: :int, init: {v1: 0, v2: 0}},
  }

  @variables %{
    surfaced: %{type: :int, init: {robot: 0}},
  }

  @actions %{{
    a_search_for: %{
      params: [:target],
      body: [
      ],
    },
  }

  @actions %{{
    a_move: %{
      params: [:loc_id],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/found/{loc_id}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_cross_gate_40: %{
      params: [:gate],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/found/{gate}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_cross_gate_60: %{
      params: [:gate],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/found/{gate}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_touch_front_v: %{
      params: [:vampire],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/found/{vampire}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_touch_back_v: %{
      params: [:vampire],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/found/{vampire}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_surface: %{
      body: [
      ],
    },
  }

  @methods %{{
    move_task: %{
      params: [:loc_id],
      alternatives: [
        %{name: "already_there"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/loc/robot"}, b: "{loc_id}"}}
],
        }
        %{name: "search_and_move"
, subtasks: [
        [""a_search_for", "{loc_id}""]
        [""a_move", "{loc_id}""]
]
        }
      ],
    },
  }

  @methods %{{
    cross_gate_task: %{
      params: [:gate],
      alternatives: [
        %{name: "already_crossed"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/crossed_gate/{gate}"}, b: "1"}}
],
        }
        %{name: "search_cross_40"
, subtasks: [
        [""a_search_for", "{gate}""]
        [""a_cross_gate_40", "{gate}""]
]
        }
        %{name: "search_cross_60"
, subtasks: [
        [""a_search_for", "{gate}""]
        [""a_cross_gate_60", "{gate}""]
]
        }
      ],
    },
  }

  @methods %{{
    slay_vampire_task: %{
      params: [:vampire],
      alternatives: [
        %{name: "already_slayed"
, check: [
        %{eval: %{type: "math/gt", a: %{pointer: "/vampire_touched/{vampire}"}, b: "0"}}
],
        }
        %{name: "search_touch_front"
, subtasks: [
        [""a_search_for", "{vampire}""]
        [""a_touch_front_v", "{vampire}""]
]
        }
        %{name: "search_touch_back"
, subtasks: [
        [""a_search_for", "{vampire}""]
        [""a_touch_back_v", "{vampire}""]
]
        }
      ],
    },
  }

  @methods %{{
    main_task: %{
      alternatives: [
        %{name: "full_mission"
, subtasks: [
        [""move_task", "l1""]
        [""cross_gate_task", "g""]
        [""move_task", "l2""]
        [""move_task", "l3""]
        [""slay_vampire_task", "v1""]
        [""move_task", "l4""]
        [""slay_vampire_task", "v2""]
        [""move_task", "l5""]
        [""a_surface""]
]
        }
      ],
    },
  }

  @todo_list [
    [""main_task""],
]
end