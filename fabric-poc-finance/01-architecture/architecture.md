# Reference Architecture

## Medallion + Orchestration overview

```mermaid
flowchart LR
    subgraph SRC[Source Systems]
        S1[ERP - GL Extracts CSV]
        S2[CRM - Customer CSV]
        S3[Billing - Invoices CSV]
        S4[Treasury - FX Rates CSV]
    end

    subgraph LANDING[OneLake Files/landing]
        L1[/CSV drop zone/]
    end

    subgraph BRONZE[Lakehouse LH_Finance - Bronze Delta]
        B1[(bronze.gl_transactions)]
        B2[(bronze.customers)]
        B3[(bronze.invoices)]
        B4[(bronze.fx_rates)]
    end

    subgraph SILVER[Lakehouse LH_Finance - Silver Delta]
        SV1[(silver.gl_transactions)]
        SV2[(silver.customers)]
        SV3[(silver.invoices)]
        SV4[(silver.fx_rates)]
        SVR[(silver_rejects.*)]
    end

    subgraph GOLD[Warehouse WH_Finance_Gold - Star Schema]
        D1[(dim_customer SCD2)]
        D2[(dim_date)]
        D3[(dim_account)]
        F1[(fact_gl)]
        F2[(fact_invoice)]
    end

    subgraph AUDIT[Audit and Control - Warehouse]
        A1[(audit_pipeline_run)]
        A2[(audit_activity_run)]
        A3[(audit_data_quality)]
        A4[(control_watermark)]
    end

    SRC --> LANDING --> B1 & B2 & B3 & B4
    B1 --> SV1
    B2 --> SV2
    B3 --> SV3
    B4 --> SV4
    SV1 & SV2 --> F1
    SV3 & SV2 --> F2
    SV2 --> D1
    SV1 --> D3

    B1 & B2 & B3 & B4 -. rejects .-> SVR
    LANDING -.-> AUDIT
    BRONZE -.-> AUDIT
    SILVER -.-> AUDIT
    GOLD -.-> AUDIT
```

## Orchestration control-flow

```mermaid
flowchart TD
    START([Trigger - schedule or manual]) --> INIT[Set variables - RunId, LoadDate, TenantId]
    INIT --> LOG1[Log START to audit_pipeline_run]
    LOG1 --> WM[Lookup control_watermark]
    WM --> FOREACH{ForEach entity in config}
    FOREACH --> INVOKE_B[Invoke PL_BRONZE_INGEST]
    INVOKE_B -->|success| INVOKE_S[Invoke PL_SILVER_LOAD]
    INVOKE_B -->|failure| ERR[Log FAILURE + raise alert]
    INVOKE_S -->|success| RECON[Invoke NB_ROW_RECONCILIATION]
    INVOKE_S -->|failure| ERR
    RECON -->|variance ok| INVOKE_G[Invoke PL_GOLD_LOAD]
    RECON -->|variance breach| ERR
    INVOKE_G --> WMUPD[Update control_watermark]
    WMUPD --> LOG2[Log SUCCESS to audit_pipeline_run]
    ERR --> LOG3[Log FAILURE, publish Activator event]
    LOG2 --> END([End])
    LOG3 --> END
```

## Key architectural decisions

| Decision                          | Choice                                    | Rationale                                                                |
|-----------------------------------|-------------------------------------------|--------------------------------------------------------------------------|
| Storage                           | OneLake — Lakehouse Delta for B/S, Warehouse for G | Best-of-both: Spark for transform, T-SQL for BI serving.        |
| Orchestrator                      | Fabric Data Factory Pipelines             | Native, low-cost, integrates with Activator & Monitoring hub.            |
| Ingestion pattern                 | Metadata-driven Copy Activity + ForEach   | Add new source by INSERT to `config_source`; no pipeline code change.    |
| Silver transform                  | Dataflow Gen2 (Power Query) per entity    | Low-code, visual, analyst-maintainable. Reject rows routed to Warehouse. |
| Reconciliation                    | PySpark notebook                          | Hard-fails pipeline on variance breach — the one place a notebook wins.  |
| Retry policy                      | 3 retries, 30s interval on Copy & Notebook| Absorb transient OneLake / auth blips.                                   |
| Failure isolation                 | Try / Catch (`On Failure` + `On Skip`) per stage | One entity failure does not stop the batch — logged & alerted.    |
| Reconciliation                    | PySpark notebook comparing counts B↔S↔G   | Fails run when variance > configured tolerance (default 0.5%).           |
| Audit store                       | Warehouse tables (T-SQL, ACID)            | Simple to query from Power BI, supports transactional writes.            |
| Alerting                          | Fabric Activator on `audit_pipeline_run.status='Failed'` | No custom code, tenant-native.                                |
| Secrets                           | Workspace-scoped connections + Key Vault  | No credentials in pipeline JSON.                                         |
| Naming                            | `PL_`, `NB_`, `LH_`, `WH_`, `bronze.`, `silver.`, `gold.`, `audit_` | Discoverability + linting.                          |
