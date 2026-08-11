# Pipeline Build Guide

Build order (each pipeline references the previous):

| Order | Pipeline / Item                                                     | Purpose                                                       |
|-------|---------------------------------------------------------------------|---------------------------------------------------------------|
| 1     | `PL_BRONZE_INGEST`                                                  | Metadata-driven raw → Bronze copy.                            |
| 2     | `DF_SILVER_<entity>` (Dataflow Gen2, one per entity)                | Schema/DQ validation, conformant → Silver, rejects → Warehouse. |
| 3     | `PL_SILVER_LOAD`                                                    | Orchestrator wrapper that runs the dataflow + writes audit rows. |
| 4     | `NB_ROW_RECONCILIATION` (notebook)                                  | Bronze↔Silver row-count check; fails on breach.               |
| 5     | `PL_GOLD_LOAD`                                                      | Star-schema populate + SCD2 for customer dim.                 |
| 6     | `PL_MASTER_ORCHESTRATOR`                                            | Wraps 1 → 3 → 4 → 5 with ForEach + error handling.            |

**Silver design:** the Silver layer uses **Dataflow Gen2** (`df_silver_load.md`) rather than a notebook — the customer has already seen a notebook-driven medallion demo. Reconciliation stays as a notebook because it needs a hard-fail on threshold breach.

All build steps use the Fabric Data Factory UI. Where JSON snippets are shown, they are the equivalent expression to paste into a parameter/dynamic content field — you never need to hand-edit pipeline JSON.

Every pipeline uses these **six standard parameters** (declared in the Parameters tab):

| Name              | Type    | Default                                         | Notes                          |
|-------------------|---------|-------------------------------------------------|--------------------------------|
| `p_run_id`        | String  | `@pipeline().RunId`                             | Passed down to children.       |
| `p_parent_run_id` | String  | `""`                                            | Empty for master.              |
| `p_load_date`     | String  | `@formatDateTime(utcNow(),'yyyy-MM-dd')`        | Business date for the load. **Autonomous:** the default expression is evaluated at run-time, so scheduled runs never need a manual value. For scheduled triggers you can also use `@formatDateTime(trigger().scheduledTime,'yyyy-MM-dd')` — see `pl_master_orchestrator.md` §"Scheduling and autonomy". |
| `p_entity_name`   | String  | —                                               | Child pipelines only.          |
| `p_load_mode`     | String  | `Full`                                          | `Full` / `Incremental`.        |
| `p_tolerance_pct` | Float   | `0.5`                                           | Reconciliation threshold.      |

See individual pipeline docs for full step-by-step build instructions.
