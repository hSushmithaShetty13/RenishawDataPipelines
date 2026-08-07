# Pipeline Build Guide

Build order (each pipeline references the previous):

| Order | Pipeline / Notebook                        | Purpose                                                       |
|-------|--------------------------------------------|---------------------------------------------------------------|
| 1     | `NB_UTIL_LOGGING` (notebook)               | Reusable helper for writing to `audit.*` from Spark.          |
| 2     | `PL_BRONZE_INGEST`                         | Metadata-driven raw → Bronze copy.                            |
| 3     | `PL_SILVER_LOAD`                           | Schema/DQ validation, reject-row routing.                     |
| 4     | `NB_ROW_RECONCILIATION`                    | Bronze↔Silver row-count check; fails on breach.               |
| 5     | `PL_GOLD_LOAD`                             | Star-schema populate + SCD2 for customer dim.                 |
| 6     | `PL_MASTER_ORCHESTRATOR`                   | Wraps 2 → 3 → 4 → 5 with ForEach + error handling.            |

All build steps use the Fabric Data Factory UI. Where JSON snippets are shown, they are the equivalent expression to paste into a parameter/dynamic content field — you never need to hand-edit pipeline JSON.

Every pipeline uses these **six standard parameters** (declared in the Parameters tab):

| Name              | Type    | Default                                         | Notes                          |
|-------------------|---------|-------------------------------------------------|--------------------------------|
| `p_run_id`        | String  | `@pipeline().RunId`                             | Passed down to children.       |
| `p_parent_run_id` | String  | `""`                                            | Empty for master.              |
| `p_load_date`     | String  | `@formatDateTime(utcNow(),'yyyy-MM-dd')`        | Business date for the load.    |
| `p_entity_name`   | String  | —                                               | Child pipelines only.          |
| `p_load_mode`     | String  | `Full`                                          | `Full` / `Incremental`.        |
| `p_tolerance_pct` | Float   | `0.5`                                           | Reconciliation threshold.      |

See individual pipeline docs for full step-by-step build instructions.
