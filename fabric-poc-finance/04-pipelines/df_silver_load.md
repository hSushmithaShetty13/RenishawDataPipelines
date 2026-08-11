# DF_SILVER_<entity> — Dataflow Gen2 Build Instructions

**Purpose:** replace the Silver notebook with a Dataflow Gen2 per entity. Each dataflow:
1. Reads Bronze Delta table via the Lakehouse connector.
2. Applies schema + data-quality rules using Power Query.
3. Writes conformant rows to `silver.<entity>` (Lakehouse destination).
4. Writes rejected rows to `silver_rejects.<entity>` (Warehouse destination) with `rule_code`, `run_id`, `rejected_at_utc`.
5. Returns row counts to the pipeline via **Dataflow refresh output** so audit tables can be populated by the pipeline's Script activity — **no code required inside the dataflow to log audit**.

You will create four dataflows (one per entity). They share the same pattern; only the DQ rules differ.

## Why Dataflow Gen2 (customer story)
- **Low-code visual transforms** — analysts can maintain rules without Spark skills.
- **Native Lakehouse + Warehouse destinations** with schema mapping in the UI.
- **CI/CD friendly** — Dataflow Gen2 items sync to Fabric Git, same as pipelines.
- **Reuse of Power Query skills** from Power BI / Excel / ADF Mapping Data Flows.
- **Incremental refresh** available for large fact entities.
- **Automatic staging in OneLake** — you get lineage in Purview out of the box.

## Prerequisites
- `WH_Finance_Gold` reject tables already created (see `03-sql/02_silver_ddl.sql`).
- Bronze tables populated by `PL_BRONZE_INGEST`.
- Lakehouse `LH_Finance` in the same workspace as the dataflow.

---

## Pattern (applied to each entity)

### Step 1 — Create the Dataflow Gen2
Workspace → **+ New item** → **Dataflow Gen2** → name `DF_SILVER_<entity>` (e.g. `DF_SILVER_gl_transactions`). Choose **Dataflow Gen2 with CI/CD (preview)** if available — this is the Git-friendly variant.

### Step 2 — Add a Lakehouse source query
1. **Get data** → **Lakehouse** → select `LH_Finance` → table `bronze.<entity>`.
2. Rename query to `bronze_source`.

### Step 3 — Add pipeline parameters (public parameters)
Home ribbon → **Manage parameters** → **New parameter**:

| Name          | Type | Required | Default   |
|---------------|------|----------|-----------|
| `p_run_id`    | Text | Yes      | `manual`  |
| `p_load_date` | Text | Yes      | `1900-01-01` |

These become bindable inputs when the pipeline calls the dataflow.

### Step 4 — Duplicate the source into two branches

Right-click `bronze_source` → **Reference** twice:
- `q_conforming` — will become the Silver output.
- `q_rejects`    — will become the reject-table output.

### Step 5 — Add DQ rules in a single "Add custom column" step

In `bronze_source` add a custom column named `_rule_code`. Paste the entity-specific M expression from the tables below. First non-null match wins.

Then in:
- `q_conforming`: `Table.SelectRows(#"Prev Step", each [_rule_code] = null)` then `Table.RemoveColumns(_, {"_rule_code"})`.
- `q_rejects`: `Table.SelectRows(#"Prev Step", each [_rule_code] <> null)` then add columns:
  - `run_id`          = `p_run_id`
  - `rejected_at_utc` = `DateTime.FixedUtcNow()`
  - `raw_row`         = `Text.Combine(List.Transform(Record.FieldValues(_),(v)=>Text.From(v)),"|")`

### Step 6 — Configure output destinations

**q_conforming → Add destination**
- Type: **Lakehouse**
- Lakehouse: `LH_Finance`
- Table: `silver.<entity>`
- Update method: **Replace** (Full) or **Append** (Incremental) — match `control.source_config.load_mode`.

**q_rejects → Add destination**
- Type: **Warehouse**
- Warehouse: `WH_Finance_Gold`
- Table: `silver_rejects.<entity>`
- Update method: **Append**
- Column mapping: verify `rule_code`, `run_id`, `rejected_at_utc`, `raw_row` map correctly.

### Step 7 — Publish
Home → **Publish**. Wait for validation.

### Step 8 — Verify refresh outputs
Refresh once manually and note the **RowsWritten** value shown in the refresh history (per query). The pipeline reads this in the next section.

---

## DQ rules per entity

### gl_transactions

```m
= if [customer_id] = null or [customer_id] = "" then "NULL_CUSTOMER_ID"
  else if not List.Contains({"GBP","USD","EUR","JPY","CHF"}, [currency_code]) then "INVALID_CURRENCY"
  else if [amount] = 0 then null  // Warn only — kept in Silver
  else null
```

### customers

```m
= if [customer_name] = null then "NULL_NAME"
  else if Text.Length([country_code]) <> 2 then null  // Warn only
  else null
```

Duplicate detection is a separate step in `q_rejects` for `customers`:
```m
= let
    dupes = Table.SelectRows(
        Table.Group(bronze_source, {"customer_id"}, {{"cnt", each Table.RowCount(_), Int64.Type}}),
        each [cnt] > 1)[customer_id]
  in
    Table.AddColumn(bronze_source, "_rule_code", each
        if List.Contains(dupes, [customer_id]) then "DUPLICATE_CUSTOMER"
        else if [customer_name] = null then "NULL_NAME"
        else null)
```

### invoices

```m
= if [amount] < 0 then "NEGATIVE_AMOUNT"
  else if [customer_id] = null then "MISSING_CUSTOMER"
  else null
```

### fx_rates

No rejects — copy Bronze straight to Silver (still put it in a dataflow for consistency and lineage).

---

## Pipeline wiring — PL_SILVER_LOAD (updated)

Replace the previous Notebook activity with a **Dataflow activity**.

### Activity graph

```mermaid
flowchart LR
    A[Set variable: v_start = utcNow] --> B[Dataflow: DF_SILVER_&lt;entity&gt;]
    B --> C[Lookup: SELECT COUNT(*) FROM silver.&lt;entity&gt; AS written]
    C --> D[Lookup: SELECT COUNT(*), rule_code FROM silver_rejects.&lt;entity&gt; WHERE run_id=@ GROUP BY rule_code]
    D --> E[Script: sp_log_activity Succeeded]
    D --> F[Script: sp_log_dq per rule]
    B -. On Failure .-> G[Script: sp_log_activity Failed] --> H[Fail]
```

### Steps

**1. `DF_Silver_Run` — Dataflow activity**
- Dataflow: pick `DF_SILVER_<entity>` (dynamic content: `@concat('DF_SILVER_', pipeline().parameters.p_entity_name)`).
- Compute type: default.
- Public parameters (bind pipeline params to the dataflow params from Step 3):
  - `p_run_id`    ← `@pipeline().parameters.p_run_id`
  - `p_load_date` ← `@pipeline().parameters.p_load_date`
- Retry: 2, Retry interval: 60 s.

**2. `LKP_Silver_Count` — Lookup on Warehouse**
```sql
-- Lakehouse table exposed via SQL endpoint of LH_Finance
SELECT COUNT_BIG(*) AS rows_written
FROM   LH_Finance.silver.@{pipeline().parameters.p_entity_name};
```
Use dynamic content to build the fully-qualified name safely (three-part name via cross-database query, or run the Lookup against the Lakehouse SQL endpoint directly).

**3. `LKP_Reject_Counts` — Lookup on Warehouse**
```sql
SELECT rule_code,
       COUNT_BIG(*) AS rows_failed,
       MAX(CONCAT('silver_rejects.', '@{pipeline().parameters.p_entity_name}')) AS reject_table
FROM   silver_rejects.@{pipeline().parameters.p_entity_name}
WHERE  run_id = '@{pipeline().parameters.p_run_id}'
GROUP  BY rule_code;
```
- **First row only:** unchecked (we want the array).

**4. `SCR_Log_Activity_Success` — Script**
```sql
DECLARE @written  BIGINT = @{activity('LKP_Silver_Count').output.firstRow.rows_written};
DECLARE @reject   BIGINT = (
    SELECT ISNULL(SUM(rows_failed),0)
    FROM OPENJSON(N'@{string(activity('LKP_Reject_Counts').output.value)}')
         WITH (rows_failed BIGINT '$.rows_failed'));

EXEC audit.sp_log_activity
    @run_id           = '@{pipeline().parameters.p_run_id}',
    @activity_run_id  = '@{activity('DF_Silver_Run').ActivityRunId}',
    @pipeline_name    = 'PL_SILVER_LOAD',
    @activity_name    = 'DF_Silver_Run',
    @activity_type    = 'Dataflow',
    @entity_name      = '@{pipeline().parameters.p_entity_name}',
    @layer            = 'Silver',
    @start_time_utc   = '@{variables('v_start')}',
    @end_time_utc     = '@{utcNow()}',
    @status           = 'Succeeded',
    @rows_written     = @written,
    @rows_rejected    = @reject;
```

**5. `SCR_Log_DQ` — Script (one row per rule)**
```sql
INSERT INTO audit.data_quality(run_id, entity_name, rule_code, rule_description, severity, rows_failed, reject_table)
SELECT '@{pipeline().parameters.p_run_id}',
       '@{pipeline().parameters.p_entity_name}',
       JSON_VALUE(r.value,'$.rule_code'),
       JSON_VALUE(r.value,'$.rule_code'),
       'Reject',
       CAST(JSON_VALUE(r.value,'$.rows_failed') AS BIGINT),
       JSON_VALUE(r.value,'$.reject_table')
FROM   OPENJSON(N'@{string(activity('LKP_Reject_Counts').output.value)}') r;
```

**6. `SCR_Log_Activity_Failure` — Script (On Failure of `DF_Silver_Run`)**
```sql
EXEC audit.sp_log_activity
    @run_id           = '@{pipeline().parameters.p_run_id}',
    @activity_run_id  = '@{activity('DF_Silver_Run').ActivityRunId}',
    @pipeline_name    = 'PL_SILVER_LOAD',
    @activity_name    = 'DF_Silver_Run',
    @activity_type    = 'Dataflow',
    @entity_name      = '@{pipeline().parameters.p_entity_name}',
    @layer            = 'Silver',
    @start_time_utc   = '@{variables('v_start')}',
    @end_time_utc     = '@{utcNow()}',
    @status           = 'Failed',
    @error_code       = '@{activity('DF_Silver_Run').Error.ErrorCode}',
    @error_message    = '@{activity('DF_Silver_Run').Error.Message}';
```
Then **Fail activity** to bubble up.

---

## Reconciliation stays as a notebook

`NB_ROW_RECONCILIATION` is unchanged — a small PySpark notebook is the pragmatic choice for a row-count parity check because Dataflow Gen2 doesn't expose an easy "fail-the-pipeline-on-condition" primitive without extra plumbing.

The customer message: **use the right tool for each job — Dataflow Gen2 for declarative transforms, notebooks only where they add clear value (recon, complex logic, ML).**
