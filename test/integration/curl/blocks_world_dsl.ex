# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

name "blocks_world"
variable :pos, type: :ref, init: %{a: "b", b: "table", c: "table"}
variable :clear, type: :bool, init: %{a: true, b: false, c: true}
variable :holding, type: :bool, init: %{hand: false}

action :a_pickup,
  params: [:block],
  body: [
    condition(:math/eq, pointer_get("/pos/{block}"), "table"),
    condition(:math/eq, pointer_get("/clear/{block}"), true),
    condition(:math/eq, pointer_get("/holding/hand"), false),
    pointer_set("/pos/{block}", "hand"),
    pointer_set("/clear/{block}", false),
    pointer_set("/holding/hand", "{block}")
  ]

method :get,
  params: [:block],
  alternatives: [
    alt(:pickup_from_table,
      check: [condition(:math/eq, pointer_get("/pos/{block}"), "table")],
      subtasks: [[":a_pickup", "{block}"]]
    ),
    alt(:unstack, subtasks: [[":a_unstack", "{block}"]])
  ]

todo_list [[":get", "a"]]