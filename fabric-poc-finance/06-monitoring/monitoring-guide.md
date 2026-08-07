# Monitoring & Alerting Setup

## 1. Fabric Monitoring hub (built-in)

Home → **Monitor** → filter Item type = **Data pipeline**, Workspace = `WS_Finance_POC`.

Everything you need for a demo is already there:
- Run status, duration, activity-level drill-down.
- Consumption (CU-seconds) per run.
- **Rerun** and **Rerun from failed activity** buttons.

Rename the Monitor view **"Finance POC — Last 24h"** and save as a shortcut for the demo.

## 2. Custom audit dashboard (Power BI)

Point a semantic model at `WH_Finance_Gold` with these five tables:
- `audit.pipeline_run`
- `audit.activity_run`
- `audit.data_quality`
- `audit.reconciliation`
- `control.watermark`

Recommended pages:
1. **Executive KPIs** — success rate today, total rows processed, total rejected, avg duration.
2. **Runs timeline** — Gantt of pipeline runs coloured by status.
3. **Data quality** — bar chart of `rows_failed` by `rule_code` and entity.
4. **Reconciliation** — variance% per entity vs tolerance threshold line.

Example DAX for success rate:
```
Success Rate % =
DIVIDE(
    CALCULATE( COUNTROWS('pipeline_run'), 'pipeline_run'[status] = "Succeeded" ),
    COUNTROWS( 'pipeline_run' )
)
```

## 3. Alerting via Fabric Activator (Reflex)

Two rules cover the POC scope.

### Rule A — Pipeline failure
- **Source:** Warehouse `WH_Finance_Gold`, query
  ```sql
  SELECT run_id, pipeline_name, error_message, end_time_utc
  FROM audit.pipeline_run
  WHERE status = 'Failed'
    AND end_time_utc >= DATEADD(minute,-15,SYSUTCDATETIME());
  ```
- **Schedule:** every 5 minutes.
- **Condition:** rowcount > 0.
- **Action:** send Teams message to `#finance-data-alerts` and email the on-call DE.

### Rule B — Reconciliation breach
- **Source query:**
  ```sql
  SELECT run_id, entity_name, variance_pct, tolerance_pct
  FROM audit.reconciliation
  WHERE passed = 0
    AND checked_at_utc >= DATEADD(minute,-15,SYSUTCDATETIME());
  ```
- **Action:** Teams + email + create a Fabric Item Comment on the master pipeline.

### Rule C — Rejected-row spike (optional stretch)
Alert when `SUM(rows_failed)` per entity in the last 24h exceeds 3× 7-day median.

## 4. Diagnostic logs to Log Analytics (production, out of scope for demo)

Workspace settings → **Diagnostic settings** → send `PipelineRuns`, `ActivityRuns`, `TriggerRuns` categories to a Log Analytics workspace. Enables long-term retention and cross-workspace KQL queries.
