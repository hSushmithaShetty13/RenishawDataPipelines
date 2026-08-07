"""
Generate a small, deterministic Finance dummy dataset for the Fabric POC.

Run:
    python generate_finance_data.py

Outputs to ./bronze/:
    gl_transactions.csv  (~5,000 rows)
    customers.csv        (~200 rows, includes deliberate DQ issues)
    invoices.csv         (~1,500 rows)
    fx_rates.csv         (~365 rows)

Deliberate data-quality issues injected so the demo can showcase rejected-row
handling in the Silver load:
    * NULL customer_id on ~1% of GL rows
    * Negative amounts on ~0.5% of invoices
    * Duplicate customer_id (2 rows)
    * Unknown currency codes on ~0.3% of GL rows
"""

import csv
import os
import random
from datetime import date, timedelta

random.seed(42)
OUT = os.path.join(os.path.dirname(__file__), "bronze")
os.makedirs(OUT, exist_ok=True)

CURRENCIES = ["GBP", "USD", "EUR", "JPY", "CHF"]
ACCOUNTS = [f"4{str(i).zfill(4)}" for i in range(1000, 1050)]  # 50 GL accounts
COST_CENTRES = [f"CC{str(i).zfill(3)}" for i in range(1, 21)]
COUNTRIES = ["GB", "US", "DE", "JP", "CH", "FR", "IE", "NL"]

START = date(2026, 1, 1)
END = date(2026, 7, 31)


def rand_date():
    delta = (END - START).days
    return START + timedelta(days=random.randint(0, delta))


# ---------------- customers.csv ----------------
customers = []
for cid in range(1000, 1200):
    customers.append({
        "customer_id": cid,
        "customer_name": f"Customer_{cid}",
        "country_code": random.choice(COUNTRIES),
        "segment": random.choice(["Enterprise", "SMB", "Public"]),
        "created_date": rand_date().isoformat(),
        "is_active": random.choice([1, 1, 1, 0]),
    })
# Duplicate customer to trigger DQ reject
customers.append(dict(customers[5]))
customers.append(dict(customers[10]))

with open(os.path.join(OUT, "customers.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(customers[0].keys()))
    w.writeheader()
    w.writerows(customers)

# ---------------- gl_transactions.csv ----------------
gl_rows = []
for txn_id in range(1, 5001):
    cid = random.choice(customers)["customer_id"]
    ccy = random.choice(CURRENCIES)
    # Inject DQ issues
    if random.random() < 0.01:
        cid = ""  # NULL customer_id
    if random.random() < 0.003:
        ccy = "ZZZ"  # invalid currency
    gl_rows.append({
        "txn_id": txn_id,
        "posting_date": rand_date().isoformat(),
        "account_code": random.choice(ACCOUNTS),
        "cost_centre": random.choice(COST_CENTRES),
        "customer_id": cid,
        "currency_code": ccy,
        "amount": round(random.uniform(-5000, 50000), 2),
        "description": f"GL posting {txn_id}",
        "source_system": "ERP",
    })

with open(os.path.join(OUT, "gl_transactions.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(gl_rows[0].keys()))
    w.writeheader()
    w.writerows(gl_rows)

# ---------------- invoices.csv ----------------
inv_rows = []
for inv_id in range(1, 1501):
    amount = round(random.uniform(100, 25000), 2)
    if random.random() < 0.005:
        amount = -abs(amount)  # invalid negative invoice
    inv_rows.append({
        "invoice_id": inv_id,
        "customer_id": random.choice(customers)["customer_id"],
        "invoice_date": rand_date().isoformat(),
        "due_date": (rand_date() + timedelta(days=30)).isoformat(),
        "currency_code": random.choice(CURRENCIES),
        "amount": amount,
        "status": random.choice(["OPEN", "PAID", "OVERDUE"]),
    })
with open(os.path.join(OUT, "invoices.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(inv_rows[0].keys()))
    w.writeheader()
    w.writerows(inv_rows)

# ---------------- fx_rates.csv ----------------
fx = []
d = START
while d <= END:
    for ccy in CURRENCIES:
        rate = {
            "GBP": 1.0, "USD": 1.27, "EUR": 1.17, "JPY": 190.0, "CHF": 1.10
        }[ccy] * random.uniform(0.98, 1.02)
        fx.append({
            "rate_date": d.isoformat(),
            "from_ccy": ccy,
            "to_ccy": "GBP",
            "rate": round(rate, 6),
        })
    d += timedelta(days=1)
with open(os.path.join(OUT, "fx_rates.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(fx[0].keys()))
    w.writeheader()
    w.writerows(fx)

print("Generated:")
for name in ["gl_transactions.csv", "customers.csv", "invoices.csv", "fx_rates.csv"]:
    p = os.path.join(OUT, name)
    print(f"  {p}  ({sum(1 for _ in open(p)) - 1} rows)")
