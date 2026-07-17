# Skill Allocation Problem — Adaptation from MiniZinc to HTN Planning

## Overview

The **skill allocation problem** is a workforce planning optimization challenge adapted from the
[minizinc-2025-problems](https://github.com/fire/minizinc-2025-problems) repository
(`skill-allocation` directory). It addresses the practical challenge of assigning service jobs to
engineers while managing skill gaps through targeted training.

**Problem Statement:**
- Given a pool of engineers with existing skills
- A set of service jobs, each requiring a specific skill
- Constraints on job capacity, training budget, and geographic limitations
- Find an allocation of jobs to engineers that minimizes the total number of new skills that must be trained

## Original Problem (MiniZinc)

### Model: `skill_allocation_only.mzn`

The MiniZinc formulation is a constraint satisfaction problem with optimization:

```
Variables:
  allocations[JOBS] ∈ ENGS          # job → engineer assignment
  new_skills[ENGS, TRAINING] ∈ {0} ∪ SKILLS  # engineer → learned skills (matrix)

Constraints:
  1. Skill Coverage: Each job's required skill must be held (or learned) by the assigned engineer
  2. Training Limit: Total new skills trained ≤ nTrainingCap
  3. Job Limits: Min/max jobs per engineer
  4. Geographic: Caps on overseas and interstate job assignments
  5. Skill Limits: Each engineer learns at most nNewSkillsPerPerson new skills

Objective: minimize(sum of new_skills trained)
```

### Sample Data: `skill_allocation_mzn_1m_2.dzn`

The 1-month instance #2 includes:
- **62 engineers** with partial skill coverage (binary 62×83 matrix)
- **83 specialized skills** (sk1–sk83)
- **400+ service jobs**, each specifying:
  - Required skill (priority index)
  - Duration
  - Location (postcode)
  - Overseas flag
- **Constraints:**
  - nNewSkillsPerPerson = 1 (each engineer learns at most 1 new skill)
  - nMaxJobs = 10 (cap on jobs per engineer)
  - nOverseasCap = 5 (limit overseas assignments per engineer)

## HTN Planning Adaptation

### Design Rationale

The MiniZinc problem is **constraint optimization** (CSP/MIP). HTN planning is **goal-driven task decomposition**.
The adaptation preserves the core allocation challenge while reformulating it in hierarchical planning terms:

| Aspect | MiniZinc | HTN Planning |
|--------|----------|--------------|
| **Decision Model** | Simultaneous allocation of all jobs | Sequential task decomposition |
| **Search Strategy** | Constraint propagation & branch-and-bound | Backward-chaining hierarchical decomposition |
| **State Representation** | Logical constraints | Imperative state variables (pointers) |
| **Scalability** | Suited to precise optimization | Suited to stepwise refinement and replanning |

### Domain Definition: `skill_allocation.jsonld`

#### State Variables

```json
{
  "engineer_skills": {
    "type": "int",
    "description": "Binary: engineer_skills[e][s] = 1 if e has s"
  },
  "job_requirements": {
    "type": "int",
    "description": "[skill, priority, duration, location, is_overseas]"
  },
  "allocations": {
    "type": "ref",
    "description": "allocations[job_id] = engineer_id"
  },
  "new_skills": {
    "type": "int",
    "description": "Tracked training assignments (minimized)"
  },
  "training_budget": {
    "type": "int",
    "description": "Cumulative training used"
  }
}
```

#### Actions

1. **`assign_job(job_id, engineer_id, skill_to_train?)`**
   - Assigns a job to an engineer
   - Pre-trains if engineer lacks the required skill (up to budget)
   - Guards enforce skill coverage and budget limits

2. **`train_engineer(engineer_id, skill_id)`**
   - Grants a skill to an engineer
   - Increments training budget

#### Methods (Hierarchical Decomposition)

```
allocate_all_jobs
  ├─ allocate_one_then_rest
  │  ├─ allocate_next_job
  │  │  ├─ assign_to_qualified_engineer  [if engineer has skill]
  │  │  └─ train_and_assign              [if engineer must learn skill]
  │  └─ allocate_all_jobs  [recursive]
  └─ all_jobs_done  [base case]
```

### Problem Instances

#### 1. `skill_allocation_simple.jsonld`

**Simplified demonstration** (3 engineers, 5 jobs, 5 skills):
- Shows core allocation challenge in tractable size
- Clear engineer-skill-job relationships
- Illustrates training trade-offs

**Data:**
```
Engineers:  eng1 (sk1, sk2, sk5)
            eng2 (sk2, sk3, sk4)
            eng3 (sk1, sk3, sk5)

Jobs:       job1 (requires sk1)
            job2 (requires sk2)
            job3 (requires sk3)
            job4 (requires sk4)  ← only eng2 has it
            job5 (requires sk5)

Constraints: max 3 trainings allowed
```

**Optimal Plan:**
```
Assign job4 to eng2         (eng2 has sk4)
Assign job1 to eng1         (eng1 has sk1)
Assign job2 to eng2         (eng2 has sk2)
Assign job3 to eng3         (eng3 has sk3)
Train eng2 on sk5, assign job5 to eng2  (1 training)
OR
Assign job5 to eng1         (eng1 has sk5)
```
→ Total trainings: 0–1 (depending on allocation strategy)

#### 2. `skill_allocation_medium.jsonld`

**Realistic scale** (10 engineers, 20 skills, 15 jobs) derived from `skill_allocation_mzn_1m_2.dzn`:
- Reduced version of the full 62-engineer, 83-skill, 400-job instance
- Represents a regional service allocation scenario
- Includes geographic constraints (overseas/interstate)

**Data Abstraction:**
- Actual engineer-skill matrix simplified to 10×20 core subset
- Jobs grouped by skill distribution
- Training budget: 5 (vs. unlimited or cap in MiniZinc instance)

## Problem Characteristics

### Difficulty Factors

1. **Combinatorial Explosion:** Job→Engineer assignments are exponential in job count
2. **Skill Gaps:** Not all engineers have all skills; training fills gaps
3. **Budget Constraint:** Limited training slots force careful allocation choices
4. **Secondary Constraints:** Geographic, capacity, and per-engineer limits add complexity
5. **Optimization Goal:** Minimizing training makes it harder than just satisfying coverage

### Suitability for Planning

✅ **Why HTN Planning Fits:**
- Sequential decomposition aligns with real job dispatch workflows
- Replanning is natural: if an engineer becomes unavailable, replan remaining jobs
- Preference orderings (e.g., minimize training before geographically dispersing jobs) map to method alternatives
- State is imperative: easy to track "job 5 assigned to eng2" and "eng2 trained on skill 7"

⚠️ **Limitations vs. Pure CSP:**
- HTN planning finds *a feasible plan*, not necessarily the optimal allocation
- Greedy method choices may not lead to global optimum (search strategy matters)
- Scaling to 400+ jobs requires efficient decomposition and pruning

## Future Enhancements

1. **Larger instances:** Use full 62-engineer, 83-skill, 400-job dataset with more sophisticated search heuristics
2. **Capability-based preferences:** Integrate with ReBAC graph to prefer engineers with related skills
3. **Dynamic constraints:** Model job urgency and engineer availability changes
4. **Multi-objective trade-offs:** Balance training cost vs. job disparity vs. travel distance
5. **Replanning scenarios:** Simulate engineer unavailability and plan reassignments

## References

- **MiniZinc Benchmark:** https://github.com/MiniZinc/minizinc-2025-problems
- **Source Data:** `minizinc-2025-problems/skill-allocation/`
- **HTN Planning Concepts:** See `docs/rectgtn.md` for RECTGTN model details
- **JSONLD Schema:** `priv/schemas/rectgtn_domain.schema.json`

---

**Adaptation Date:** 2026-07-16  
**Adapted By:** Claude Code / iFire  
**Original Authors (MiniZinc Problems):** MiniZinc Community
