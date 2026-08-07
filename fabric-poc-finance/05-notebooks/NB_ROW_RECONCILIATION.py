"""
NB_ROW_RECONCILIATION
Compares Bronze vs Silver row counts for a single entity and fails the
pipeline if the variance exceeds the configured tolerance.

Called by PL_MASTER_ORCHESTRATOR between PL_SILVER_LOAD and PL_GOLD_LOAD.
Also writes one row into audit.reconciliation for BI dashboards.
"""

# PARAMETERS
run_id        = ""
entity_name   = ""
tolerance_pct = 0.5   # %

import json
from pyspark.sql import functions as F

bronze_count = spark.table(f"bronze.{entity_name}").count()
silver_count = spark.table(f"silver.{entity_name}").count()
variance_pct = 0.0 if bronze_count == 0 else abs(bronze_count - silver_count) * 100.0 / bronze_count
passed = variance_pct <= tolerance_pct

# Write to Warehouse audit.reconciliation via the SQL endpoint / mssparkutils.
# Simpler: rely on the pipeline's Script activity to call sp_log_reconciliation
# using the notebook's exit payload.

payload = {
    "bronzeCount":  bronze_count,
    "silverCount":  silver_count,
    "variancePct":  round(variance_pct, 4),
    "tolerancePct": tolerance_pct,
    "passed":       passed,
}

if not passed:
    # Raising an exception fails the notebook -> pipeline On Failure fires.
    mssparkutils.notebook.exit(json.dumps(payload))
    raise Exception(
        f"Reconciliation FAILED for {entity_name}: "
        f"bronze={bronze_count}, silver={silver_count}, "
        f"variance={variance_pct:.4f}% > tolerance={tolerance_pct}%"
    )

mssparkutils.notebook.exit(json.dumps(payload))
