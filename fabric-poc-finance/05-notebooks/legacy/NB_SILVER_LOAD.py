"""
NB_SILVER_LOAD
Import into Fabric as a Notebook and attach to Lakehouse LH_Finance.
Called by PL_SILVER_LOAD once per entity.

Reads:  bronze.<entity_name> Delta
Writes: silver.<entity_name> Delta                (conformant rows)
        silver_rejects.<entity_name> Delta        (rejected rows + rule_code)
Exits:  JSON payload consumed by the pipeline for audit.data_quality logging.
"""

# PARAMETERS (Fabric parameter cell)
run_id       = ""
entity_name  = ""
load_date    = ""

# ------------------------------------------------------------------
import json
from datetime import datetime
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

BRONZE_TABLE  = f"bronze.{entity_name}"
SILVER_TABLE  = f"silver.{entity_name}"
REJECT_TABLE  = f"silver_rejects.{entity_name}"

df = spark.table(BRONZE_TABLE)
rows_read = df.count()

# ------------------------------------------------------------------
# Per-entity DQ rules. severity=Reject removes the row; severity=Warn keeps it.
RULES = {
    "gl_transactions": [
        ("NULL_CUSTOMER_ID",  "Reject", F.col("customer_id").isNull() | (F.col("customer_id") == "")),
        ("INVALID_CURRENCY",  "Reject", ~F.col("currency_code").isin("GBP","USD","EUR","JPY","CHF")),
        ("ZERO_AMOUNT",       "Warn",   F.col("amount") == 0),
    ],
    "customers": [
        ("DUPLICATE_CUSTOMER","Reject", None),   # handled separately below
        ("NULL_NAME",         "Reject", F.col("customer_name").isNull()),
        ("INVALID_COUNTRY",   "Warn",   F.length("country_code") != 2),
    ],
    "invoices": [
        ("NEGATIVE_AMOUNT",   "Reject", F.col("amount") < 0),
        ("MISSING_CUSTOMER",  "Reject", F.col("customer_id").isNull()),
    ],
    "fx_rates": [],
}

rules = RULES.get(entity_name, [])

# Build a single rule_code column (first-match) and split
df = df.withColumn("_rule_code", F.lit(None).cast(StringType()))

# Handle duplicate detection for customers
if entity_name == "customers":
    dup_ids = (df.groupBy("customer_id").count().where("count > 1").select("customer_id"))
    df = df.join(dup_ids, "customer_id", "left") \
           .withColumn("_rule_code",
                       F.when(F.col("count").isNotNull() & F.col("_rule_code").isNull(), F.lit("DUPLICATE_CUSTOMER"))
                        .otherwise(F.col("_rule_code"))) \
           .drop("count")

for code, severity, expr in rules:
    if expr is None:
        continue
    if severity == "Reject":
        df = df.withColumn("_rule_code",
                           F.when(expr & F.col("_rule_code").isNull(), F.lit(code)).otherwise(F.col("_rule_code")))

rejects_df   = df.filter(F.col("_rule_code").isNotNull())
conforming_df = df.filter(F.col("_rule_code").isNull()).drop("_rule_code")

rows_rejected = rejects_df.count()
rows_written  = conforming_df.count()

# ------------------------------------------------------------------
# Persist conformant rows to Silver (overwrite for simplicity in POC)
(conforming_df.write.format("delta").mode("overwrite")
     .option("overwriteSchema","true").saveAsTable(SILVER_TABLE))

# Persist rejected rows with audit columns
if rows_rejected > 0:
    audit_rejects = (rejects_df
        .withColumnRenamed("_rule_code", "rule_code")
        .withColumn("run_id",         F.lit(run_id))
        .withColumn("rejected_at_utc",F.lit(datetime.utcnow())))
    (audit_rejects.write.format("delta").mode("append")
        .option("mergeSchema","true").saveAsTable(REJECT_TABLE))

# ------------------------------------------------------------------
# Per-rule breakdown for audit.data_quality
rule_summary = []
if rows_rejected > 0:
    breakdown = (rejects_df.groupBy("_rule_code").count().collect())
    for r in breakdown:
        rule_summary.append({
            "rule_code":    r["_rule_code"],
            "rows_failed":  r["count"],
            "severity":     "Reject",
            "reject_table": REJECT_TABLE,
        })

payload = {
    "rowsRead":     rows_read,
    "rowsWritten":  rows_written,
    "rowsRejected": rows_rejected,
    "rules":        rule_summary,
}

mssparkutils.notebook.exit(json.dumps(payload))
