# 60-Minute Demo Runbook

## Prep checklist (10 min before)
- [ ] Sign into Fabric as demo account with Contributor on `WS_Finance_POC`.
- [ ] `Files/landing/*` cleared. Drop **today's** CSVs by copying `02-data/bronze/*.csv` into `Files/landing/<entity>/2026/08/07/`.
- [ ] Open browser tabs: (1) `PL_MASTER_ORCHESTRATOR` canvas, (2) Fabric **Monitor** hub, (3) Power BI audit dashboard, (4) `WH_Finance_Gold` SQL editor with `SELECT TOP 20 * FROM audit.pipeline_run ORDER BY start_time_utc DESC` pre-typed.
- [ ] Warm-up run completed successfully so the capacity is hot.
- [ ] "Cold" DQ scenario ready: a second CSV variant `gl_transactions_bad.csv` with 30% invalid currencies to trigger reject-row demo.

---

## Talk track

### 0. Set the scene (2 min)
> "You already have data in OneLake — the question is how to move it reliably, prove it moved correctly, and know within minutes if it didn't. That's what this POC shows."

### 1. Architecture (5 min) — slide from `01-architecture/architecture.md`
Cover: OneLake single copy, Lakehouse for Bronze/Silver, Warehouse for Gold + Audit, Pipelines as the control plane, Activator for alerts.

### 2. Show the master pipeline (5 min)
Open `PL_MASTER_ORCHESTRATOR`. Point out:
- Parameters (`p_run_id`, `p_load_date`, etc.) — no hard-coding.
- `LKP_Get_Entities` reads `control.source_config` — **new entities require zero pipeline changes**.
- ForEach with parallelism=4.
- On-Failure branch on every Invoke — resilient, not fragile.

### 3. Run it live (3 min)
Click **Run** with `p_load_date = 2026-08-07`. Immediately switch to Monitor.

### 4. Bronze ingest deep dive (8 min)
Drill into a Copy activity while it runs.
- Show **Details** → `rowsRead / rowsCopied / rowsSkipped`.
- Open Settings → **Fault tolerance = Skip incompatible** and **Log path** — this is how rejected rows are captured.
- Run the T-SQL:
  ```sql
  SELECT * FROM audit.activity_run WHERE run_id = '<paste>' AND layer='Bronze';
  ```
  Show `rows_rejected` populated.

### 5. Silver load — rejection routing (8 min)
Switch to the `NB_SILVER_LOAD` notebook activity output.
- Show the `exitValue` JSON with per-rule counts.
- Query `audit.data_quality WHERE run_id=<>` — one row per rule.
- Query the actual reject table:
  ```sql
  SELECT TOP 20 * FROM silver_rejects.gl_transactions ORDER BY rejected_at_utc DESC;
  ```
- Show a rejected row's `rule_code` = `INVALID_CURRENCY`.

### 6. Reconciliation (5 min)
Open `NB_ROW_RECONCILIATION` output. Explain variance formula.
Then run the **bad-file scenario**: drop `gl_transactions_bad.csv` and rerun.
- The recon notebook fails.
- Pipeline stops before Gold — **corruption prevented**.
- Activator alert fires → show Teams notification.

### 7. Audit dashboard (5 min)
Switch to Power BI. Walk through the four pages. Emphasise that everything on the dashboard comes from three tables — no bespoke logging code per pipeline.

### 8. Best-practices scorecard (5 min)
Open `08-best-practices/best-practices.md` on screen. Highlight the ✅ items and be honest about the ⚠️ items still to harden for production.

### 9. Q&A (8 min)
Anticipate:
- **Cost?** — CU consumption visible per run in Monitor.
- **CI/CD?** — Fabric Git integration + deployment pipelines; workspace = branch mapping.
- **Security?** — Workspace roles + item-level permissions + row-level security on Gold.
- **Scaling?** — ForEach `BatchCount` + capacity size; Copy activity autoscale on ingress.

---

## Reset procedure (post-demo)

```sql
TRUNCATE TABLE audit.pipeline_run;
TRUNCATE TABLE audit.activity_run;
TRUNCATE TABLE audit.data_quality;
TRUNCATE TABLE audit.reconciliation;
DELETE FROM control.watermark;
```
Delete Silver reject tables via Lakehouse UI. Reload `control.source_config` seed if needed.
