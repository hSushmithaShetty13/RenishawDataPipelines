# 09 — Additional / Interests

Implementation notes for the 🔜 items in [`08-best-practices/best-practices.md`](../08-best-practices/best-practices.md) — the things we deliberately kept out of the POC scope but that customers usually ask about right after the demo.

Each section is a **short, opinionated how-to** with the minimum steps to stand it up, not a full design doc. Order matches the scorecard.

---

## 1. Diagnostic logs → Log Analytics

**Value:** cross-workspace KQL, 90-day+ retention, integration with existing Sentinel / Azure Monitor.

**Steps:**
1. Create a Log Analytics workspace in the same tenant.
2. Fabric admin portal → **Tenant settings** → enable **Workspace-level diagnostics**.
3. In `WS_Finance_POC` → **Workspace settings** → **Diagnostic settings** → **Add**:
   - Categories: `PipelineRuns`, `ActivityRuns`, `TriggerRuns`, `SemanticModelRefresh`.
   - Destination: your Log Analytics workspace.
4. Wait ~15 min, then in Log Analytics run:
   ```kql
   FabricPipelineRuns
   | where TimeGenerated > ago(1h)
   | summarize Runs=count(), Failed=countif(Status=="Failed") by PipelineName
   ```
5. Save as a **workbook** and pin to the Ops dashboard.

**Effort:** 30 min. **Cost:** LA ingestion, ~£2/GB.

---

## 2. SLO dashboards (success rate, MTTR, MTBF)

**Value:** operational maturity signal for the platform team.

**Steps:**
1. In the existing Power BI audit model, add three DAX measures:
   ```
   Success Rate 30d =
     VAR total = CALCULATE(COUNTROWS(pipeline_run), pipeline_run[start_time_utc] >= TODAY()-30)
     VAR ok    = CALCULATE(COUNTROWS(pipeline_run), pipeline_run[status]="Succeeded", pipeline_run[start_time_utc] >= TODAY()-30)
     RETURN DIVIDE(ok, total)

   MTTR minutes =
     AVERAGEX(
       FILTER(pipeline_run, pipeline_run[status]="Succeeded" && RELATED(prev[status])="Failed"),
       DATEDIFF(RELATED(prev[end_time_utc]), pipeline_run[end_time_utc], MINUTE))

   MTBF hours =
     DIVIDE(
       DATEDIFF(MIN(pipeline_run[start_time_utc]), MAX(pipeline_run[start_time_utc]), HOUR),
       CALCULATE(COUNTROWS(pipeline_run), pipeline_run[status]="Failed"))
   ```
2. New page **"SLO"** with 3 KPI cards + a 90-day trend line for Success Rate.
3. Set an SLO target line (e.g. 99.0%) using a constant-line reference.

**Effort:** 45 min.

---

## 3. Financial totals reconciliation (SUM parity)

**Value:** row-count parity can pass while a currency-conversion bug halves totals — SUM checks catch value drift.

**Steps:**
1. Extend `audit.reconciliation` with two columns:
   ```sql
   ALTER TABLE audit.reconciliation ADD bronze_amount DECIMAL(20,2) NULL, silver_amount DECIMAL(20,2) NULL, amount_variance_pct DECIMAL(9,4) NULL;
   ```
2. In `NB_ROW_RECONCILIATION.py`, add for numeric entities:
   ```python
   b_amt = spark.table(f"bronze.{entity_name}").agg(F.sum("amount")).first()[0] or 0
   s_amt = spark.table(f"silver.{entity_name}").agg(F.sum("amount")).first()[0] or 0
   amt_var = 0 if b_amt == 0 else abs(b_amt - s_amt) * 100.0 / abs(b_amt)
   passed = passed and amt_var <= tolerance_pct
   ```
3. Include `bronze_amount`, `silver_amount`, `amount_variance_pct` in the exit payload and add columns to the Script call.

**Effort:** 20 min.

---

## 4. Event-based trigger on file arrival (OneLake events)

**Value:** near-real-time ingestion; no more "waiting for the 2 AM schedule".

**Steps:**
1. Workspace → **+ New item** → **Reflex / Activator**.
2. Add event source → **OneLake events** → path `Files/landing/**` → event type `FileCreated`.
3. Add action → **Run Fabric pipeline** → `PL_MASTER_ORCHESTRATOR` with parameters:
   - `p_load_date` = `@formatDateTime(triggerBody().eventTime,'yyyy-MM-dd')`
   - `p_entity_name` derived from the file path (regex on `triggerBody().subject`).
4. Disable the daily schedule or keep it as a safety-net.

**Effort:** 30 min.
**Caveat:** OneLake events are in preview at time of writing — check GA status for prod use.

---

## 5. Tumbling-window trigger (exactly-once, back-fill capable)

**Value:** deterministic time windows, automatic dependency chaining, safe replays.

**Steps:**
1. `PL_MASTER_ORCHESTRATOR` → **Schedule** → **New tumbling window trigger**.
2. Frequency: `1 day`, start time yesterday 02:00 UTC.
3. Pass window start/end as pipeline parameters:
   - `p_load_date` = `@trigger().outputs.windowStartTime`
4. Set **max concurrency = 1** and **retry policy 2 × 30 min** on the trigger itself — Fabric handles state, so a re-run for the same window is idempotent by design.

**Effort:** 20 min.

---

## 6. Managed Identity for Warehouse / Lakehouse connections

**Value:** no user credentials in pipeline JSON; survives leaver events.

**Steps:**
1. Workspace → **Manage connections and gateways** → **+ Connection** → type **Fabric Warehouse** / **Fabric Lakehouse**.
2. Authentication → **Workspace Identity** (or **Service principal** if you need cross-tenant).
3. Grant that identity `db_datareader` + `db_datawriter` in `WH_Finance_Gold`.
4. Edit every Script / Copy / Lookup activity → switch its connection to the new one.
5. Delete any user-scoped connections that are no longer referenced.

**Effort:** 40 min for the whole workspace.

---

## 7. Key Vault for external secrets

**Value:** when you extend the POC to on-prem SQL, SFTP, API sources.

**Steps:**
1. Create an Azure Key Vault; grant the Workspace Identity `Key Vault Secrets User`.
2. In the connection dialog for any external source, pick **Azure Key Vault** as the auth method and reference the secret by name.
3. Never store the secret string in the pipeline expression itself.

**Effort:** 20 min per source.

---

## 8. Row-level security on Gold

**Value:** finance data restricted to entity/region owners for BI consumers.

**Steps:**
1. In `WH_Finance_Gold` create a security predicate:
   ```sql
   CREATE FUNCTION gold.fn_country_predicate(@country VARCHAR(10))
   RETURNS TABLE WITH SCHEMABINDING AS
   RETURN SELECT 1 AS ok
   FROM   security.user_country
   WHERE  upn = SUSER_SNAME() AND country_code = @country;

   CREATE SECURITY POLICY gold.pol_country
     ADD FILTER PREDICATE gold.fn_country_predicate(country_code) ON gold.dim_customer
     WITH (STATE = ON);
   ```
2. Populate `security.user_country` from AAD group membership (manual for POC, sync from Entra for prod).
3. Verify by connecting as two different users in Power BI.

**Effort:** 60 min.

---

## 9. Fabric Git integration (workspace ↔ repo)

**Value:** all pipeline / dataflow / notebook JSON in source control; PR-based promotion.

**Steps:**
1. Workspace settings → **Git integration** → connect to `hSushmithaShetty13/RenishawDataPipelines`, branch `fabric/dev`, folder `fabric-items/`.
2. Fabric will offer to sync existing items → confirm.
3. New workflow:
   - Change something in the Dev workspace → **Source control** icon → **Commit** to `fabric/dev`.
   - Raise PR → `main`.
   - Prod workspace is bound to `main` → **Update all** after merge.

**Effort:** 30 min setup, then embedded in day-to-day work.

---

## 10. CU consumption alert per pipeline

**Value:** catch cost spikes before month-end billing surprise.

**Steps:**
1. Fabric admin installs **Microsoft Fabric Capacity Metrics** app from AppSource.
2. Open the app → open the **Items (14 days)** table in the semantic model.
3. Add a Reflex (Activator) rule:
   - Object: `Items (14 days)`
   - Condition: `CU(s)` for `ItemName = 'PL_MASTER_ORCHESTRATOR'` > `<threshold>` over `1 day`.
   - Action: Teams message to `#finance-data-alerts`.
4. Optionally add a `Capacity CU %` threshold rule (>80% for 15 min) as a global backstop.

**Effort:** 15 min once the Capacity Metrics app is installed.
**Blocker:** app installation is a **Fabric admin** action — typically not available inside a POC.

---

## How to use this section in the demo

- **Do not** walk through it slide-by-slide — customer will glaze over.
- Close the best-practices scorecard, say: *"For every 🔜 item you saw, we've written a 15-to-60-minute how-to in section 09. Happy to run any of them as a follow-up."*
- Have this file open in a browser tab so you can jump to a specific point if asked.
