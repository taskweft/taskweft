# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule job_shop_scheduling do
  use Taskweft.DSL

  @name "job_shop_scheduling"

  @variables %{
    task_status: %{type: :int, init: {job1_taskA: 0, job1_taskB: 0, job2_taskC: 0, job2_taskD: 0}},
  }

  @variables %{
    machine_avail: %{type: :int, init: {machine1: 1, machine2: 1}},
  }

  @actions %{{
    a_start_task: %{
      params: [:job_task, :machine],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/task_status/{job_task}"}, b: "0"}}
        %{eval: %{type: "math/eq", a: %{pointer: "/machine_avail/{machine}"}, b: "1"}}
      ],
    },
  }

  @actions %{{
    a_finish_task: %{
      params: [:job_task, :machine],
      body: [
        %{eval: %{type: "math/eq", a: %{pointer: "/task_status/{job_task}"}, b: "1"}}
      ],
    },
  }

  @methods %{{
    schedule_task: %{
      params: [:job_task, :machine],
      alternatives: [
        %{name: "already_done"
, check: [
        %{eval: %{type: "math/eq", a: %{pointer: "/task_status/{job_task}"}, b: "2"}}
],
        }
        %{name: "start_and_finish"
, subtasks: [
        [""a_start_task", "{job_task}", "{machine}""]
        [""a_finish_task", "{job_task}", "{machine}""]
]
        }
      ],
    },
  }

  @todo_list [
    [""schedule_task", "job1_taskA", "machine1""],
    [""schedule_task", "job1_taskB", "machine2""],
    [""schedule_task", "job2_taskC", "machine2""],
    [""schedule_task", "job2_taskD", "machine1""],
]
end