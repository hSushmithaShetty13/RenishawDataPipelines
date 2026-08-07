/* ============================================================
   03_gold_ddl.sql
   Gold star schema in WH_Finance_Gold.
   Populated by PL_GOLD_LOAD via T-SQL Script/Copy activities.
   ============================================================ */

CREATE SCHEMA gold;
GO

CREATE TABLE gold.dim_date (
    date_key        INT           NOT NULL PRIMARY KEY NONCLUSTERED,
    calendar_date   DATE          NOT NULL,
    day             INT           NOT NULL,
    month           INT           NOT NULL,
    month_name      VARCHAR(20)   NOT NULL,
    quarter         INT           NOT NULL,
    year            INT           NOT NULL,
    fiscal_period   VARCHAR(10)   NULL,
    is_weekend      BIT           NOT NULL
);
GO

CREATE TABLE gold.dim_customer (
    customer_sk     BIGINT        NOT NULL,        -- surrogate
    customer_id     VARCHAR(50)   NOT NULL,        -- business key
    customer_name   VARCHAR(200)  NOT NULL,
    country_code    VARCHAR(10)   NULL,
    segment         VARCHAR(50)   NULL,
    is_active       BIT           NOT NULL,
    valid_from_utc  DATETIME2(3)  NOT NULL,
    valid_to_utc    DATETIME2(3)  NULL,           -- NULL = current
    is_current      BIT           NOT NULL
);
GO

CREATE TABLE gold.dim_account (
    account_sk      BIGINT        NOT NULL,
    account_code    VARCHAR(20)   NOT NULL,
    account_name    VARCHAR(200)  NULL,
    account_type    VARCHAR(50)   NULL
);
GO

CREATE TABLE gold.fact_gl (
    txn_id          BIGINT        NOT NULL,
    date_key        INT           NOT NULL,
    customer_sk     BIGINT        NULL,
    account_sk      BIGINT        NOT NULL,
    cost_centre     VARCHAR(20)   NULL,
    currency_code   VARCHAR(10)   NOT NULL,
    amount_ccy      DECIMAL(18,2) NOT NULL,
    amount_gbp      DECIMAL(18,2) NOT NULL,
    fx_rate         DECIMAL(18,6) NOT NULL,
    source_system   VARCHAR(50)   NOT NULL,
    load_run_id     VARCHAR(50)   NOT NULL,
    load_date       DATE          NOT NULL
);
GO

CREATE TABLE gold.fact_invoice (
    invoice_id      BIGINT        NOT NULL,
    date_key        INT           NOT NULL,
    due_date_key    INT           NOT NULL,
    customer_sk     BIGINT        NOT NULL,
    currency_code   VARCHAR(10)   NOT NULL,
    amount_ccy      DECIMAL(18,2) NOT NULL,
    amount_gbp      DECIMAL(18,2) NOT NULL,
    status          VARCHAR(20)   NOT NULL,
    load_run_id     VARCHAR(50)   NOT NULL,
    load_date       DATE          NOT NULL
);
GO
