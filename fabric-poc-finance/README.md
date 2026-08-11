# Microsoft Fabric POC — Finance Pipeline Orchestration & Operational Excellence

**Audience:** Customer technical stakeholders (Data Engineering, Platform, Ops)
**Duration:** 60 minutes
**Focus:** Pipeline orchestration, monitoring, auditing, alerting — NOT transformation logic.

Demonstrates how Microsoft Fabric Data Factory pipelines orchestrate, monitor, audit and operationalise a Bronze → Silver → Gold Lakehouse flow using a Finance dataset (GL transactions, Customers, Invoices, FX Rates).

---

## 1-Hour Session Agenda

| # | Section                                          | Time  | Deliverable Referenced                     |
|---|--------------------------------------------------|-------|---------------------------------------------|
| 1 | Business context & POC objectives                | 5 min | `07-demo-script/demo-runbook.md` §1         |
| 2 | Reference architecture walkthrough               | 5 min | `01-architecture/architecture.md`           |
| 3 | Bronze ingestion — parameterised Copy Activity   | 8 min | `04-pipelines/pl_bronze_ingest.md`          |
| 4 | Silver load via Dataflow Gen2 — DQ + reject routing | 8 min | `04-pipelines/df_silver_load.md`         |
| 5 | Gold load — SCD, reconciliation, publish         | 7 min | `04-pipelines/pl_gold_load.md`              |
| 6 | Audit tables — success / failure / rejected rows | 7 min | `03-sql/01_audit_tables.sql`                |
| 7 | Monitoring, alerting, Activator rules            | 7 min | `06-monitoring/`                            |
| 8 | Operational best-practices scorecard             | 5 min | `08-best-practices/best-practices.md`       |
| 9 | Q&A                                              | 8 min | —                                           |

---

## Folder Layout

```
fabric-poc-finance/
├── 01-architecture/       Reference architecture, medallion diagram, control-flow diagram
├── 02-data/               Finance dummy dataset + generator script
├── 03-sql/                Audit + Silver + Gold DDL (Warehouse / Lakehouse SQL endpoint)
├── 04-pipelines/          Step-by-step build guide for every pipeline
├── 05-notebooks/          Reconciliation + audit reporting notebooks (PySpark)
├── 06-monitoring/         Monitoring, alerting, Activator setup
├── 07-demo-script/        60-minute talk track / runbook
├── 08-best-practices/     Microsoft-recommended patterns checklist
├── 09-additional-interests/ How-to notes for the 🔜 items not in POC scope
└── README.md
```

---

## What You Will See In The Demo

1. **A Master Orchestrator pipeline** (`PL_MASTER_ORCHESTRATOR`) invokes child pipelines in the correct order with parameters.
2. **Bronze ingest** copies raw CSV → Lakehouse `Files/bronze/<entity>/<yyyy>/<mm>/<dd>/` with full audit row.
3. **Silver load** (Dataflow Gen2 per entity) applies schema + quality checks, writes conformant rows to `silver.<entity>` and routes rejects to `silver_rejects.<entity>` — a Script activity in the pipeline logs counts to `audit.data_quality`.
4. **Gold load** performs reconciliation (source vs Silver vs Gold row counts) — pipeline FAILS if variance > tolerance.
5. **Audit dashboard** driven by three tables: `audit_pipeline_run`, `audit_activity_run`, `audit_data_quality`.
6. **Alerting** via Fabric Activator on failed runs and reconciliation variance.

---

## Prerequisites

- Fabric capacity (F2 minimum for POC)
- One workspace: `WS_Finance_POC`
- One Lakehouse: `LH_Finance` (Bronze + Silver as Delta tables)
- One Warehouse: `WH_Finance_Gold` (Gold star schema + audit tables)
- Contributor role for the demo user

---

## How To Rebuild This POC In Your Tenant

Follow the numbered folders **in order**:

1. `02-data/` — run `generate_finance_data.py` locally OR upload the provided CSVs to OneLake `Files/landing/`.
2. `03-sql/` — execute all three scripts in the Warehouse SQL editor.
3. `04-pipelines/` — build each pipeline exactly as documented (screenshots referenced by activity name).
4. `05-notebooks/` — import the two `.py` files as Fabric notebooks and attach to `LH_Finance`.
5. `06-monitoring/` — configure Activator rules.
6. `07-demo-script/` — rehearse using the runbook.

Total build time: **~2 hours** for an engineer familiar with Fabric.

## Autonomy

The pipeline is designed to run **hands-off on a schedule** — no one types a date. `p_load_date` defaults to `@formatDateTime(utcNow(),'yyyy-MM-dd')`, evaluated at run time. Manual override is only used for back-fills. See `04-pipelines/pl_master_orchestrator.md` §"Scheduling and autonomy" for the recommended `trigger().scheduledTime` and tumbling-window variants.

---

## Reference

Structure inspired by publicly available Fabric training patterns (e.g. github.com/ineslantero/fabric-training-cmi) and Microsoft's official Data Factory in Fabric best-practice guidance.
