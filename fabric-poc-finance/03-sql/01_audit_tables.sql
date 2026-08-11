/* ============================================================
   01_audit_tables.sql
   Warehouse: WH_Finance_Gold  (Microsoft Fabric Warehouse)
   Purpose: control + audit tables for the Fabric POC.

   Fabric Warehouse T-SQL notes (differs from SQL Server / Azure SQL):
     * DEFAULT constraints are NOT supported -> defaults are supplied by the
       stored procedures below at INSERT time.
     * PRIMARY KEY must be NONCLUSTERED NOT ENFORCED.
     * IDENTITY, SEQUENCE, and computed columns are NOT supported.
     * MERGE is NOT supported -> use DELETE + INSERT pattern (see sp_update_watermark).
   ============================================================ */

CREATE SCHEMA audit;
GO
CREATE SCHEMA control;
GO

/* ---------- Pipeline-level run log ---------- */
CREATE TABLE audit.pipeline_run (
    run_id              VARCHAR(50)   NOT NULL,
    parent_run_id       VARCHAR(50)   NULL,
    pipeline_name       VARCHAR(200)  NOT NULL,
    trigger_type        VARCHAR(50)   NOT NULL,
    triggered_by        VARCHAR(200)  NULL,
    load_date           DATE          NOT NULL,
    start_time_utc      DATETIME2(3)  NOT NULL,
    end_time_utc        DATETIME2(3)  NULL,
    duration_sec        INT           NULL,
    status              VARCHAR(20)   NOT NULL,
    error_code          VARCHAR(100)  NULL,
    error_message       VARCHAR(4000) NULL,
    rows_read           BIGINT        NULL,
    rows_written        BIGINT        NULL,
    rows_rejected       BIGINT        NULL,
    inserted_at_utc     DATETIME2(3)  NOT NULL
);
GO

/* ---------- Activity-level run log ---------- */
CREATE TABLE audit.activity_run (
    run_id              VARCHAR(50)   NOT NULL,
    activity_run_id     VARCHAR(50)   NOT NULL,
    pipeline_name       VARCHAR(200)  NOT NULL,
    activity_name       VARCHAR(200)  NOT NULL,
    activity_type       VARCHAR(50)   NOT NULL,
    entity_name         VARCHAR(200)  NULL,
    layer               VARCHAR(20)   NULL,
    start_time_utc      DATETIME2(3)  NOT NULL,
    end_time_utc        DATETIME2(3)  NULL,
    duration_sec        INT           NULL,
    status              VARCHAR(20)   NOT NULL,
    rows_read           BIGINT        NULL,
    rows_written        BIGINT        NULL,
    rows_rejected       BIGINT        NULL,
    rows_skipped        BIGINT        NULL,
    error_code          VARCHAR(100)  NULL,
    error_message       VARCHAR(4000) NULL,
    inserted_at_utc     DATETIME2(3)  NOT NULL
);
GO

/* ---------- Data-quality rejection log ---------- */
CREATE TABLE audit.data_quality (
    run_id              VARCHAR(50)   NOT NULL,
    entity_name         VARCHAR(200)  NOT NULL,
    rule_code           VARCHAR(100)  NOT NULL,
    rule_description    VARCHAR(500)  NOT NULL,
    severity            VARCHAR(20)   NOT NULL,
    rows_failed         BIGINT        NOT NULL,
    reject_table        VARCHAR(400)  NULL,
    detected_at_utc     DATETIME2(3)  NOT NULL
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
    checked_at_utc      DATETIME2(3)  NOT NULL
);
GO

/* ---------- High-watermark control table ---------- */
CREATE TABLE control.watermark (
    entity_name         VARCHAR(200)  NOT NULL,
    watermark_column    VARCHAR(200)  NOT NULL,
    watermark_value     VARCHAR(200)  NOT NULL,
    last_updated_utc    DATETIME2(3)  NOT NULL,
    CONSTRAINT PK_watermark PRIMARY KEY NONCLUSTERED (entity_name) NOT ENFORCED
);
GO

/* ---------- Metadata-driven source config ---------- */
CREATE TABLE control.source_config (
    entity_name         VARCHAR(200)  NOT NULL,
    source_path         VARCHAR(500)  NOT NULL,
    file_pattern        VARCHAR(200)  NOT NULL,
    bronze_table        VARCHAR(200)  NOT NULL,
    silver_table        VARCHAR(200)  NOT NULL,
    load_mode           VARCHAR(20)   NOT NULL,
    watermark_column    VARCHAR(200)  NULL,
    tolerance_pct       DECIMAL(9,4)  NOT NULL,
    is_active           BIT           NOT NULL,
    CONSTRAINT PK_source_config PRIMARY KEY NONCLUSTERED (entity_name) NOT ENFORCED
);
GO

INSERT INTO control.source_config
    (entity_name, source_path, file_pattern, bronze_table, silver_table, load_mode, watermark_column, tolerance_pct, is_active)
VALUES
    ('gl_transactions','Files/landing/gl_transactions/','*.csv','bronze.gl_transactions','silver.gl_transactions','Incremental','posting_date',0.5,1),
    ('customers',      'Files/landing/customers/',      '*.csv','bronze.customers',      'silver.customers',      'Full',       NULL,           0.0,1),
    ('invoices',       'Files/landing/invoices/',       '*.csv','bronze.invoices',       'silver.invoices',       'Incremental','invoice_date', 0.5,1),
    ('fx_rates',       'Files/landing/fx_rates/',       '*.csv','bronze.fx_rates',       'silver.fx_rates',       'Full',       NULL,           0.0,1);
GO

/* ============================================================
   Stored procedures — supply "default" values here since Fabric
   Warehouse doesn't support DEFAULT constraints on columns.
   ============================================================ */

CREATE PROCEDURE audit.sp_log_pipeline_start
    @run_id VARCHAR(50), @parent_run_id VARCHAR(50), @pipeline_name VARCHAR(200),
    @trigger_type VARCHAR(50), @triggered_by VARCHAR(200), @load_date DATE
AS
BEGIN
    INSERT INTO audit.pipeline_run(run_id,parent_run_id,pipeline_name,trigger_type,triggered_by,load_date,start_time_utc,status,inserted_at_utc)
    VALUES(@run_id,@parent_run_id,@pipeline_name,@trigger_type,@triggered_by,@load_date,SYSUTCDATETIME(),'Started',SYSUTCDATETIME());
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
        rows_rejected,rows_skipped,error_code,error_message,inserted_at_utc)
    VALUES(@run_id,@activity_run_id,@pipeline_name,@activity_name,@activity_type,
        @entity_name,@layer,@start_time_utc,@end_time_utc,
        DATEDIFF(SECOND,@start_time_utc,@end_time_utc),@status,
        @rows_read,@rows_written,@rows_rejected,@rows_skipped,@error_code,@error_message,SYSUTCDATETIME());
END;
GO

CREATE PROCEDURE audit.sp_log_dq
    @run_id VARCHAR(50), @entity_name VARCHAR(200),
    @rule_code VARCHAR(100), @rule_description VARCHAR(500),
    @severity VARCHAR(20), @rows_failed BIGINT, @reject_table VARCHAR(400)
AS
BEGIN
    INSERT INTO audit.data_quality(run_id,entity_name,rule_code,rule_description,severity,rows_failed,reject_table,detected_at_utc)
    VALUES(@run_id,@entity_name,@rule_code,@rule_description,@severity,@rows_failed,@reject_table,SYSUTCDATETIME());
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
        variance_pct,tolerance_pct,passed,checked_at_utc)
    VALUES(@run_id,@entity_name,@bronze_count,@silver_count,@gold_count,
        @variance,@tolerance_pct,
        CASE WHEN @variance <= @tolerance_pct THEN 1 ELSE 0 END,
        SYSUTCDATETIME());
END;
GO

/* Fabric Warehouse does not support MERGE. Emulate with DELETE + INSERT. */
CREATE PROCEDURE control.sp_update_watermark
    @entity_name VARCHAR(200), @watermark_column VARCHAR(200), @watermark_value VARCHAR(200)
AS
BEGIN
    DELETE FROM control.watermark WHERE entity_name = @entity_name;
    INSERT INTO control.watermark(entity_name,watermark_column,watermark_value,last_updated_utc)
    VALUES(@entity_name,@watermark_column,@watermark_value,SYSUTCDATETIME());
END;
GO
