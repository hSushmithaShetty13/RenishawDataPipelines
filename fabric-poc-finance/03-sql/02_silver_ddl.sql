/* ============================================================
   02_silver_ddl.sql
   Silver-layer Delta tables are created by the notebooks on
   first write, but for BI-friendly SQL access we expose them
   as Warehouse SHORTCUTS or MIRROR views. This script defines
   the reject-row target tables in the Warehouse for auditing.
   ============================================================ */

CREATE SCHEMA silver_rejects;
GO

CREATE TABLE silver_rejects.gl_transactions (
    run_id          VARCHAR(50),
    rejected_at_utc DATETIME2(3),
    rule_code       VARCHAR(100),
    txn_id          VARCHAR(50),
    posting_date    VARCHAR(50),
    account_code    VARCHAR(50),
    cost_centre     VARCHAR(50),
    customer_id     VARCHAR(50),
    currency_code   VARCHAR(10),
    amount          VARCHAR(50),
    description     VARCHAR(500),
    source_system   VARCHAR(50),
    raw_row         VARCHAR(4000)
);
GO

CREATE TABLE silver_rejects.customers (
    run_id          VARCHAR(50),
    rejected_at_utc DATETIME2(3),
    rule_code       VARCHAR(100),
    customer_id     VARCHAR(50),
    customer_name   VARCHAR(200),
    country_code    VARCHAR(10),
    segment         VARCHAR(50),
    created_date    VARCHAR(50),
    is_active       VARCHAR(10),
    raw_row         VARCHAR(4000)
);
GO

CREATE TABLE silver_rejects.invoices (
    run_id          VARCHAR(50),
    rejected_at_utc DATETIME2(3),
    rule_code       VARCHAR(100),
    invoice_id      VARCHAR(50),
    customer_id     VARCHAR(50),
    invoice_date    VARCHAR(50),
    due_date        VARCHAR(50),
    currency_code   VARCHAR(10),
    amount          VARCHAR(50),
    status          VARCHAR(20),
    raw_row         VARCHAR(4000)
);
GO
