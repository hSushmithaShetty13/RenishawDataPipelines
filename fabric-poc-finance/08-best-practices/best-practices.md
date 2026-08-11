# Microsoft-Recommended Fabric Data Factory Best Practices — POC Scorecard

Legend:  ✅ implemented in POC   ⚠️ demonstrated but hardening needed for prod   🔜 out of POC scope

## Pipeline design
- ✅ **Metadata-driven ingestion** — new sources via `control.source_config`, no pipeline edits.
- ✅ **Parameterise everything** — no hard-coded paths, dates, table names.
- ✅ **Standardised parameter set** across all pipelines (`p_run_id`, `p_load_date`, …).
- ✅ **Single Master Orchestrator** with ForEach + child Invoke-pipeline pattern.
- ✅ **Isolate stages** into Bronze / Silver / Gold pipelines (blast-radius control).
- ✅ **Right tool per stage** — Copy activity for ingest, **Dataflow Gen2** for Silver DQ (low-code), notebook only for reconciliation, T-SQL Scripts for Gold merge.
- ⚠️ **Idempotency** — Silver dataflow uses `Replace` for full loads; production should use MERGE by business key via Warehouse destination.

## Error handling
- ✅ **On Success / On Failure** paths on every activity.
- ✅ **Retry policy** (3 × 30 s) on Copy and Notebook activities.
- ✅ **Fail activity** used to bubble child failures to master.
- ✅ **Reject routing** — Copy fault-tolerance + Silver rule engine → dedicated reject tables.
- ⚠️ **Poison-message quarantine** for Silver rejects (auto-move after N days).

## Monitoring & alerting
- ✅ Central **audit schema** in Warehouse with three tables + reconciliation.
- ✅ **Activator** rules on failure + variance breach.
- ✅ **Power BI audit dashboard** driven by audit tables.
- 🔜 **Diagnostic logs → Log Analytics** for cross-workspace KQL and 90-day retention.
- 🔜 **SLO dashboards** — success rate, MTTR, MTBF.

## Auditing
- ✅ Every pipeline logs START and END rows in `audit.pipeline_run`.
- ✅ Every activity logs row-level metrics in `audit.activity_run` incl. `rows_rejected`.
- ✅ Every DQ rule breach logged in `audit.data_quality` with pointer to reject table.
- ✅ Every Bronze↔Silver check logged in `audit.reconciliation`.
- ⚠️ **Immutable audit** — enable Delta table history + retention policy on `audit.*`.

## Data quality
- ✅ Rule-code driven rejects with severity `Reject` vs `Warn`.
- ✅ Reject tables mirror source schema + append `run_id`, `rule_code`, `rejected_at_utc`.
- ⚠️ Rule catalogue managed in code today — move to `control.dq_rule` table for governance.

## Reconciliation
- ✅ Automated Bronze ↔ Silver row-count check per entity.
- ✅ Configurable **tolerance %** per entity in `control.source_config`.
- ✅ Pipeline **fails hard** when tolerance breached → Gold layer protected.
- 🔜 Financial totals reconciliation (SUM(amount) parity) in addition to row counts.

## Scheduling & triggers
- ✅ Time-based schedule on master (`02:00 UTC daily`).
- 🔜 **Event-based trigger** on new file arrival (OneLake events).
- 🔜 **Tumbling window** trigger for exactly-once semantics with dependency chains.

## Security
- ✅ Workspace roles used for RBAC; no user-embedded connections.
- ⚠️ **Managed Identity** for Warehouse connection (POC uses user creds).
- 🔜 **Key Vault** integration for any external secrets.
- 🔜 **Row-level security** on Gold tables for BI consumers.

## CI/CD & governance
- 🔜 **Fabric Git integration** — workspace ↔ Azure Repos branch (`main` = prod).
- 🔜 **Deployment pipelines** — Dev → Test → Prod with variable libraries.
- 🔜 **Item-level Purview lineage**.

## Cost
- ✅ ForEach batch-count tuned to capacity (start 4).
- ✅ Small notebook session sizes for POC.
- 🔜 CU consumption alert per pipeline (Activator on Monitor telemetry).

---
Use this as the closing slide — customers respond to a self-critical scorecard.

For **how to implement** the 🔜 items above, see [`09-additional-interests/README.md`](../09-additional-interests/README.md) — short how-to notes (15–60 min each) covering Log Analytics, SLO dashboards, SUM-based reconciliation, event triggers, tumbling windows, Managed Identity, Key Vault, RLS, Git integration, deployment pipelines, Purview lineage and CU consumption alerts.
