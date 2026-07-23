# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule rescue do
  use Taskweft.DSL

  @name "rescue"

  @variables %{
    loc: %{type: :int, init: {r1: 0, w1: 1, p1: 2, a1: 3}},
  }

  @variables %{
    robot_type: %{type: :int, init: {r1: 0, w1: 0, a1: 1}},
  }

  @variables %{
    has_medicine: %{type: :int, init: {a1: 0, w1: 0, r1: 0}},
  }

  @variables %{
    status: %{type: :int, init: {r1: 0, w1: 0, a1: 3, p1: 3}},
  }

  @variables %{
    altitude: %{type: :int, init: {a1: 0}},
  }

  @actions %{{
    a_free_robot: %{
      params: [:robot],
      body: [
      ],
    },
  }

  @actions %{{
    a_move_euclidean: %{
      params: [:robot, :dest],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/robot_type/{robot}"}, b: "0"}}
      ],
    },
  }

  @actions %{{
    a_move_fly: %{
      params: [:robot, :dest],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/robot_type/{robot}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_inspect_person: %{
      params: [:robot, :person],
      body: [
      ],
    },
  }

  @actions %{{
    a_inspect_location: %{
      params: [:robot, :loc_id],
    },
  }

  @actions %{{
    a_support_person: %{
      params: [:robot, :person],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/status/{person}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_change_altitude: %{
      params: [:drone, :new_alt],
      body: [
      ],
    },
  }

  @actions %{{
    a_capture_image: %{
      params: [:robot, :camera, :loc_id],
    },
  }

  @actions %{{
    a_check_real: %{
      params: [:loc_id],
    },
  }

  @methods %{{
    move_task: %{
      params: [:robot, :dest],
      alternatives: [
        %{name: "already_there"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/loc/{robot}"}, b: "{dest}"}}
],
        }
        %{name: "euclidean"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/robot_type/{robot}"}, b: "0"}}
],
, subtasks: [
        [""a_move_euclidean", "{robot}", "{dest}""]
]
        }
        %{name: "fly"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/robot_type/{robot}"}, b: "1"}}
],
, subtasks: [
        [""a_move_fly", "{robot}", "{dest}""]
]
        }
      ],
    },
  }

  @methods %{{
    rescue_task: %{
      params: [:robot, :person],
      alternatives: [
        %{name: "ground_rescue"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/robot_type/{robot}"}, b: "0"}}
],
, subtasks: [
        [""help_person_task", "{robot}", "{person}""]
]
        }
      ],
    },
  }

  @methods %{{
    help_person_task: %{
      params: [:robot, :person],
      alternatives: [
        %{name: "move_inspect_support"
, subtasks: [
        [""move_task", "{robot}", {2}"]
        [""a_inspect_person", "{robot}", "{person}""]
        [""support_task", "{robot}", "{person}""]
]
        }
      ],
    },
  }

  @methods %{{
    support_task: %{
      params: [:robot, :person],
      alternatives: [
        %{name: "support_injured"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/status/{person}"}, b: "1"}}
],
, subtasks: [
        [""a_support_person", "{robot}", "{person}""]
]
        }
      ],
    },
  }

  @methods %{{
    adjust_altitude_task: %{
      params: [:robot],
      alternatives: [
        %{name: "go_low"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/altitude/{robot}"}, b: "0"}}
],
, subtasks: [
        [""a_change_altitude", "{robot}", {1}"]
]
        }
        %{name: "go_high"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/altitude/{robot}"}, b: "1"}}
],
, subtasks: [
        [""a_change_altitude", "{robot}", {0}"]
]
        }
      ],
    },
  }

  @todo_list [
    [""rescue_task", "r1", "p1""],
]
end