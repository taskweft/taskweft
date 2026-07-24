# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule service_bringup do
  use Taskweft.DSL

  @name "service_bringup"
  @description "Generic stub-green-refactor pattern for walking items through a phased lifecycle, with optional prototype-first alternative, plus the small set of verification primitives (set_stack_ready, verify_pass, verify_scenario, set_prototype_first) that problems compose into their own per-item workflows. The domain knows nothing about which items exist, which items depend on which, what 'stack_ready' or 'pass_condition' or 'scenario' keys mean — those are problem-supplied. Entity is hardcoded to 'ifire'; fork or add a param if multi-entity planning becomes a real requirement."

  @variables %{
    phase: %{type: :int, init: {}},
    # Phase per item. 0=unstarted, 1=stub (interfaces + failing tests), 2=green (implementation passes), 3=done (refactored + documented). Key space supplied by the problem.
  }

  @variables %{
    approach: %{type: :int, init: {}},
    # Chosen implementation approach per item. 0=direct, 1=prototype_first. Set by a_set_prototype_first. Optional — problems that have no prototype-first alternatives can omit this variable.
  }

  @variables %{
    stack_ready: %{type: :int, init: {}},
    # Per-component ready flag. 0=not ready, 1=ready. Flipped by a_set_stack_ready. Key space supplied by the problem; problems that don't track stack components can omit this variable.
  }

  @variables %{
    pass_condition: %{type: :int, init: {}},
    # Per-condition verification flag. 0=unmet, 1=met. Flipped by a_verify_pass. Key space supplied by the problem; problems without verifiable pass conditions can omit this variable.
  }

  @variables %{
    scenario: %{type: :int, init: {}},
    # Per-scenario verification flag. 0=unverified, 1=verified. Flipped by a_verify_scenario. Key space supplied by the problem; problems without end-to-end scenarios can omit this variable.
  }

  @actions %{{
    a_stub: %{
      # Define interfaces and write failing tests. P7D = one Saturday.
      params: [:item, :entity],
      duration: "P7D",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "0"}}
      ],
    },
  }

  @actions %{{
    a_green: %{
      # Implement to passing tests. P14D = two Saturdays.
      params: [:item, :entity],
      duration: "P14D",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_refactor: %{
      # Clean up, document, write a one-page README. P7D = one Saturday.
      params: [:item, :entity],
      duration: "P7D",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "2"}}
      ],
    },
  }

  @actions %{{
    a_set_prototype_first: %{
      # Record that this item uses the prototype-first approach before committing to full implementation. PT0S — bookkeeping only.
      params: [:item],
      duration: "PT0S",
      body: [
      ],
    },
  }

  @actions %{{
    a_set_stack_ready: %{
      # Mark a component as ready for downstream consumers once its implementing item is done. PT0S.
      params: [:component, :entity],
      duration: "PT0S",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/stack_ready/{component}"}, b: "0"}}
      ],
    },
  }

  @actions %{{
    a_verify_pass: %{
      # Verify the named pass_condition has been met and flip it. PT0S.
      params: [:condition, :entity],
      duration: "PT0S",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/pass_condition/{condition}"}, b: "0"}}
      ],
    },
  }

  @actions %{{
    a_verify_scenario: %{
      # Run an end-to-end scenario and flip its scenario flag on success. P7D = one Saturday of demo work.
      params: [:scenario_name, :entity],
      duration: "P7D",
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/scenario/{scenario_name}"}, b: "0"}}
      ],
    },
  }

  @methods %{{
    complete_item: %{
      params: [:item],
      alternatives: [
        %{name: "done"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "3"}}
],
        }
        %{name: "resume_from_green"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "2"}}
],
, subtasks: [
        [""a_refactor", "{item}", "ifire""]
]
        }
        %{name: "resume_from_stub"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "1"}}
],
, subtasks: [
        [""a_green", "{item}", "ifire""]
        [""a_refactor", "{item}", "ifire""]
]
        }
        %{name: "direct"
, subtasks: [
        [""a_stub", "{item}", "ifire""]
        [""a_green", "{item}", "ifire""]
        [""a_refactor", "{item}", "ifire""]
]
        }
      ],
    },
  }

  @methods %{{
    complete_item_prototype_first: %{
      params: [:item],
      alternatives: [
        %{name: "done"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/phase/{item}"}, b: "3"}}
],
        }
        %{name: "direct"
, subtasks: [
        [""a_set_prototype_first", "{item}""]
        [""a_stub", "{item}", "ifire""]
        [""a_green", "{item}", "ifire""]
        [""a_green", "{item}", "ifire""]
        [""a_refactor", "{item}", "ifire""]
]
        }
      ],
    },
  }

end