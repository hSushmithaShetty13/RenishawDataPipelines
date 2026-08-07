/* ============================================================
   01_audit_tables.sql
   Warehouse: WH_Finance_Gold
   Purpose: control + audit tables for the Fabric POC.
   All pipelines write here via Script activity / Stored Procedure.
   ============================================================ */

CREATE SCHEMA audit;
GO
CREATE SCHEMA control;
GO

/* ---------- Pipeline-level run log ---------- */
CREATE TABLE audit.pipeline_run (
    run_id              VARCHAR(50)   NOT NULL,     -- Fabric pipeline runId
    parent_run_id       VARCHAR(50)   NULL,
    pipeline_name       VARCHAR(200)  NOT NULL,
    trigger_type        VARCHAR(50)   NOT NULL,     -- Manual / Scheduled / Tumbling
    triggered_by        VARCHAR(200)  NULL,
    load_date           DATE          NOT NULL,
    start_time_utc      DATETIME2(3)  NOT NULL,
    end_time_utc        DATETIME2(3)  NULL,
    duration_sec        INT           NULL,
    status              VARCHAR(20)   NOT NULL,     -- Started / Succeeded / Failed / Cancelled
    error_code          VARCHAR(100)  NULL,
    error_message       VARCHAR(4000) NULL,
    rows_read           BIGINT        NULL,
    rows_written        BIGINT        NULL,
    rows_rejected       BIGINT        NULL,
    inserted_at_utc     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Activity-level run log (one row per Copy / Notebook / Script) ---------- */
CREATE TABLE audit.activity_run (
    run_id              VARCHAR(50)   NOT NULL,
    activity_run_id     VARCHAR(50)   NOT NULL,
    pipeline_name       VARCHAR(200)  NOT NULL,
    activity_name       VARCHAR(200)  NOT NULL,
    activity_type       VARCHAR(50)   NOT NULL,     -- Copy / Notebook / Script / Lookup / ForEach
    entity_name         VARCHAR(200)  NULL,         -- e.g. gl_transactions
    layer               VARCHAR(20)   NULL,         -- Bronze / Silver / Gold
    start_time_utc      DATETIME2(3)  NOT NULL,
    end_time_utc        DATETIME2(3)  NULL,
    duration_sec        INT           NULL,
    status              VARCHAR(20)   NOT NULL,
    rows_read           BIGINT        NULL,
    rows_written        BIGINT        NULL,
    rows_rejected       BIGINT        NULL,         -- <-- rejected count for Copy fault-tolerance
    rows_skipped        BIGINT        NULL,
    error_code          VARCHAR(100)  NULL,
    error_message       VARCHAR(4000) NULL,
    inserted_at_utc     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Data-quality rejection log ----------
   Populated by Silver notebooks / Dataflows. One row = one rejection reason,
   with a pointer to the physical reject Delta table where the offending rows live.
*/
CREATE TABLE audit.data_quality (
    run_id              VARCHAR(50)   NOT NULL,
    entity_name         VARCHAR(200)  NOT NULL,
    rule_code           VARCHAR(100)  NOT NULL,     -- e.g. NULL_CUSTOMER_ID
    rule_description    VARCHAR(500)  NOT NULL,
    severity            VARCHAR(20)   NOT NULL,     -- Reject / Warn
    rows_failed         BIGINT        NOT NULL,
    reject_table        VARCHAR(400)  NULL,         -- lakehouse path to reject rows
    detected_at_utc     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Reconciliation log ---------- */
CREATE TABLE audit.reconciliation (
    run_id              VARCHAR(50)   NOT NULL,
    entity_name         VARCHAR(200)  NOT NULL,
    bronze_count        BIGINT        NOT NULL,
    silver_count        BIGINT        NOT NULL,
    gold_count          BIGINT        NULL,
    variance_pct        DECIMAL(9,4)  NOT NULL,
    tolerance_pct       DECIMAL(9,4)  NOT NULL,
    passed              BIT           NOT NULL,
    checked_at_utc      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- High-watermark control table (incremental loads) ---------- */
CREATE TABLE control.watermark (
    entity_name         VARCHAR(200)  NOT NULL PRIMARY KEY,
    watermark_column    VARCHAR(200)  NOT NULL,
    watermark_value     VARCHAR(200)  NOT NULL,     -- stored as string, cast at read time
    last_updated_utc    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- Metadata-driven source config ---------- */
CREATE TABLE control.source_config (
    entity_name         VARCHAR(200)  NOT NULL PRIMARY KEY,
    source_path         VARCHAR(500)  NOT NULL,     -- Files/landing/<entity>/
    file_pattern        VARCHAR(200)  NOT NULL,     -- *.csv
    bronze_table        VARCHAR(200)  NOT NULL,
    silver_table        VARCHAR(200)  NOT NULL,
    load_mode           VARCHAR(20)   NOT NULL,     -- Full / Incremental
    watermark_column    VARCHAR(200)  NULL,
    tolerance_pct       DECIMAL(9,4)  NOT NULL DEFAULT 0.5,
    is_active           BIT           NOT NULL DEFAULT 1
);
GO

INSERT INTO control.source_config
    (entity_name, source_path, file_pattern, bronze_table, silver_table, load_mode, watermark_column, tolerance_pct)
VALUES
    ('gl_transactions','Files/landing/gl_transactions/','*.csv','bronze.gl_transactions','silver.gl_transactions','Incremental','posting_date',0.5),
    ('customers',      'Files/landing/customers/',      '*.csv','bronze.customers',      'silver.customers',      'Full',       NULL,           0.0),
    ('invoices',       'Files/landing/invoices/',       '*.csv','bronze.invoices',       'silver.invoices',       'Incremental','invoice_date', 0.5),
    ('fx_rates',       'Files/landing/fx_rates/',       '*.csv','bronze.fx_rates',       'silver.fx_rates',       'Full',       NULL,           0.0);
GO

/* ---------- Stored procedures called from pipelines ---------- */

CREATE PROCEDURE audit.sp_log_pipeline_start
    @run_id VARCHAR(50), @parent_run_id VARCHAR(50), @pipeline_name VARCHAR(200),
    @trigger_type VARCHAR(50), @triggered_by VARCHAR(200), @load_date DATE
AS
BEGIN
    INSERT INTO audit.pipeline_run(run_id,parent_run_id,pipeline_name,trigger_type,triggered_by,load_date,start_time_utc,status)
    VALUES(@run_id,@parent_run_id,@pipeline_name,@trigger_type,@triggered_by,@load_date,SYSUTCDATETIME(),'Started');
END;
GO

CREATE PROCEDURE audit.sp_log_pipeline_end
    @run_id VARCHAR(50), @status VARCHAR(20),
    @rows_read BIGINT = NULL, @rows_written BIGINT = NULL, @rows_rejected BIGINT = NULL,
    @error_code VARCHAR(100) = NULL, @error_message VARCHAR(4000) = NULL
AS
BEGIN
    UPDATE audit.pipeline_run
    SET end_time_utc = SYSUTCDATETIME(),
        duration_sec = DATEDIFF(SECOND, start_time_utc, SYSUTCDATETIME()),
        status = @status,
        rows_read = @rows_read,
        rows_written = @rows_written,
        rows_rejected = @rows_rejected,
        error_code = @error_code,
        error_message = @error_message
    WHERE run_id = @run_id;
END;
GO

CREATE PROCEDURE audit.sp_log_activity
    @run_id VARCHAR(50), @activity_run_id VARCHAR(50), @pipeline_name VARCHAR(200),
    @activity_name VARCHAR(200), @activity_type VARCHAR(50),
    @entity_name VARCHAR(200) = NULL, @layer VARCHAR(20) = NULL,
    @start_time_utc DATETIME2(3), @end_time_utc DATETIME2(3),
    @status VARCHAR(20),
    @rows_read BIGINT = NULL, @rows_written BIGINT = NULL,
    @rows_rejected BIGINT = NULL, @rows_skipped BIGINT = NULL,
    @error_code VARCHAR(100) = NULL, @error_message VARCHAR(4000) = NULL
AS
BEGIN
    INSERT INTO audit.activity_run(run_id,activity_run_id,pipeline_name,activity_name,activity_type,
        entity_name,layer,start_time_utc,end_time_utc,duration_sec,status,rows_read,rows_written,
        rows_rejected,rows_skipped,error_code,error_message)
    VALUES(@run_id,@activity_run_id,@pipeline_name,@activity_name,@activity_type,
        @entity_name,@layer,@start_time_utc,@end_time_utc,
        DATEDIFF(SECOND,@start_time_utc,@end_time_utc),@status,
        @rows_read,@rows_written,@rows_rejected,@rows_skipped,@error_code,@error_message);
END;
GO

CREATE PROCEDURE audit.sp_log_dq
    @run_id VARCHAR(50), @entity_name VARCHAR(200),
    @rule_code VARCHAR(100), @rule_description VARCHAR(500),
    @severity VARCHAR(20), @rows_failed BIGINT, @reject_table VARCHAR(400)
AS
BEGIN
    INSERT INTO audit.data_quality(run_id,entity_name,rule_code,rule_description,severity,rows_failed,reject_table)
    VALUES(@run_id,@entity_name,@rule_code,@rule_description,@severity,@rows_failed,@reject_table);
END;
GO

CREATE PROCEDURE audit.sp_log_reconciliation
    @run_id VARCHAR(50), @entity_name VARCHAR(200),
    @bronze_count BIGINT, @silver_count BIGINT, @gold_count BIGINT,
    @tolerance_pct DECIMAL(9,4)
AS
BEGIN
    DECLARE @variance DECIMAL(9,4) =
        CASE WHEN @bronze_count = 0 THEN 0
             ELSE ABS(@bronze_count - @silver_count) * 100.0 / @bronze_count END;
    INSERT INTO audit.reconciliation(run_id,entity_name,bronze_count,silver_count,gold_count,
        variance_pct,tolerance_pct,passed)
    VALUES(@run_id,@entity_name,@bronze_count,@silver_count,@gold_count,
        @variance,@tolerance_pct, CASE WHEN @variance <= @tolerance_pct THEN 1 ELSE 0 END);
END;
GO

CREATE PROCEDURE control.sp_update_watermark
    @entity_name VARCHAR(200), @watermark_column VARCHAR(200), @watermark_value VARCHAR(200)
AS
BEGIN
    MERGE control.watermark AS tgt
    USING (SELECT @entity_name AS entity_name) AS src
       ON tgt.entity_name = src.entity_name
    WHEN MATCHED THEN UPDATE SET watermark_column=@watermark_column,
                                 watermark_value=@watermark_value,
                                 last_updated_utc=SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT(entity_name,watermark_column,watermark_value)
                          VALUES(@entity_name,@watermark_column,@watermark_value);
END;
GO
