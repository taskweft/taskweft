# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule BlocksWorld do
  use Taskweft.DSL

  @name "blocks_world"

  @variables %{
    pos: %{type: :ref, init: %{a: "b", b: "table", c: "table"}},
    clear: %{type: :bool, init: %{a: true, b: false, c: true}},
    holding: %{type: :bool, init: %{hand: false}}
  }

  @actions %{
    a_pickup: %{
      params: [:block],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer_get: "/pos/{block}"}, b: "table"}},
        %{eval: %{type: "math/eq", a: %{pointer_get: "/clear/{block}"}, b: true}},
        %{eval: %{type: "math/eq", a: %{pointer_get: "/holding/hand"}, b: false}},
        %{pointer_set: "/pos/{block}", value: "hand"},
        %{pointer_set: "/clear/{block}", value: false},
        %{pointer_set: "/holding/hand", value: "{block}"}
      ]
    },
    a_unstack: %{
      params: [:block],
      bind: [%{name: :under, pointer: "/pos/{block}"}],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer_get: "/clear/{block}"}, b: true}},
        %{eval: %{type: "math/eq", a: %{pointer_get: "/holding/hand"}, b: false}},
        %{pointer_set: "/pos/{block}", value: "hand"},
        %{pointer_set: "/clear/{block}", value: false},
        %{pointer_set: "/holding/hand", value: "{block}"},
        %{pointer_set: "/clear/{under}", value: true}
      ]
    },
    a_putdown: %{
      params: [:block],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer_get: "/pos/{block}"}, b: "hand"}},
        %{pointer_set: "/pos/{block}", value: "table"},
        %{pointer_set: "/clear/{block}", value: true},
        %{pointer_set: "/holding/hand", value: false}
      ]
    },
    a_stack: %{
      params: [:block, :target],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer_get: "/pos/{block}"}, b: "hand"}},
        %{eval: %{type: "math/eq", a: %{pointer_get: "/clear/{target}"}, b: true}},
        %{pointer_set: "/pos/{block}", value: "{target}"},
        %{pointer_set: "/clear/{block}", value: true},
        %{pointer_set: "/holding/hand", value: false},
        %{pointer_set: "/clear/{target}", value: false}
      ]
    }
  }

  @methods %{
    move_one: %{
      params: [:block, :dest],
      alternatives: [
        %{name: :get_and_put, subtasks: [["get", "{block}"], ["put", "{block}", "{dest}"]]}
      ]
    },
    get: %{
      params: [:block],
      alternatives: [
        %{name: :pickup_from_table, check: [%{eval: %{type: "math/eq", a: %{pointer_get: "/pos/{block}"}, b: "table"}}], subtasks: [["a_pickup", "{block}"]]},
        %{name: :unstack, subtasks: [["a_unstack", "{block}"]]}
      ]
    },
    put: %{
      params: [:block, :dest],
      alternatives: [
        %{name: :stack_on_block, check: [%{eval: %{type: "math/eq", a: %{pointer_get: "/holding/hand"}, b: "{block}"}}, %{eval: %{type: "math/eq", a: %{pointer_get: "/clear/{dest}"}, b: true}}], subtasks: [["a_stack", "{block}", "{dest}"]]},
        %{name: :putdown_on_table, check: [%{eval: %{type: "math/eq", a: %{pointer_get: "/holding/hand"}, b: "{block}"}}], subtasks: [["a_putdown", "{block}"]]}
      ]
    },
    pos: %{
      params: [:block, :dest],
      alternatives: [
        %{name: :move_via_hand, subtasks: [["move_one", "{block}", "{dest}"]]}
      ]
    }
  }

  @todo_list [
    [:move_one, :a, :table],
    [:move_one, :c, :b],
    [:move_one, :b, :a]
  ]
end