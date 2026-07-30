"""Import Claims.xlsx (first tab + Comments tab) into Postgres.

Populates `claims` (flat columns for now; lease/policy FKs come with the
full importer) and `claim_activity` (Comments tab, joined via Row-N position).
"""
import sys
from datetime import datetime

import pandas as pd
import psycopg2

DB = "dbname=security_deposit"
XLSX = "Claims.xlsx"

YESNO = {"Yes": True, "No": False}


def yn(v):
    return YESNO.get(v) if isinstance(v, str) else None


def num(v):
    v = pd.to_numeric(v, errors="coerce")
    return None if pd.isna(v) else float(v)


def date(v):
    if pd.isna(v):
        return None
    if isinstance(v, datetime):
        return v.date()
    return pd.to_datetime(v, errors="coerce").date() if pd.to_datetime(v, errors="coerce") is not pd.NaT else None


def text(v):
    if pd.isna(v):
        return None
    s = str(v).strip()
    return s or None


def main():
    xl = pd.ExcelFile(XLSX)
    main_df = xl.parse("Security Deposit Claims")
    main_df = main_df[main_df["Tracking Number"].notna()].reset_index(drop=True)
    # sheet row N (1-based, row 1 = header) -> dataframe position N-2
    sheet_row_of = {i + 2: i for i in range(len(main_df))}

    conn = psycopg2.connect(DB)
    cur = conn.cursor()

    # --- claims ---
    inserted = 0
    claim_id_by_row = {}  # dataframe position -> claim_id
    for i, r in main_df.iterrows():
        cur.execute(
            """INSERT INTO claims (tracking_number, claim_date, claim_amount,
                 termination_type, status, pending_docs_from_pm, approval_date,
                 approved_benefit_amount, pm_explanation, hold_reason, posted_date,
                 pm_notified_at, audit_selected, exception_flag,
                 needs_adjudication_review, tenant_info_reviewed,
                 policy_info_updated, pm_info_viewed, collections_opened)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               ON CONFLICT (tracking_number) DO NOTHING
               RETURNING claim_id""",
            (
                str(int(r["Tracking Number"])),
                date(r["Claim Date"]),
                num(r["Amount of Claim"]),
                text(r["Termination Type"]),
                text(r["Status"]),
                yn(r["Pending Docs from PM"]),
                date(r["Approval Date"]),
                num(r["Approved Benefit Amount"]),
                # PM Explanation sometimes holds text that belongs elsewhere; keep verbatim
                text(r["PM Explanation"]),
                text(r["Hold Reason"]),
                date(r["Posted Date"]),
                date(r["PM Notification of Claim Received"]),
                yn(r["Audit Selection"]),
                bool(r["Unnamed: 31"]) if not pd.isna(r["Unnamed: 31"]) else None,
                yn(r["Review Claim Adjudication"]),
                yn(r["Review Tenant Information"]),
                yn(r["Update YRIG Policy Info"]),
                yn(r["View PM Information"]),
                yn(r["Open Collections"]),
            ),
        )
        row = cur.fetchone()
        if row:
            claim_id_by_row[i] = row[0]
            inserted += 1
    print(f"claims: {inserted} inserted of {len(main_df)} rows")

    # --- claim_activity from Comments tab ---
    com = xl.parse("Comments", header=None)
    com.columns = ["row_ref", "body", "author", "ts"]
    ok, skipped = 0, []
    for _, r in com.iterrows():
        try:
            n = int(str(r["row_ref"]).replace("Row", "").strip())
            pos = sheet_row_of.get(n)
            if pos is None or pos not in claim_id_by_row:
                skipped.append(f"{r['row_ref']}: no matching claim")
                continue
            ts = datetime.strptime(str(r["ts"]).strip(), "%m/%d/%y %I:%M %p")
            cur.execute(
                """INSERT INTO claim_activity (claim_id, author, body, created_at)
                   VALUES (%s,%s,%s,%s)""",
                (claim_id_by_row[pos], text(r["author"]) or "unknown", str(r["body"]), ts),
            )
            ok += 1
        except Exception as e:  # collect, don't abort
            skipped.append(f"{r['row_ref']}: {e}")
    print(f"claim_activity: {ok} inserted, {len(skipped)} skipped")
    for s in skipped[:10]:
        print("  skipped:", s)

    conn.commit()

    # --- validation: the Row 94 thread mentions approval of $880.36 ---
    cur.execute(
        """SELECT c.tracking_number, c.approved_benefit_amount
             FROM claims c JOIN claim_activity a ON a.claim_id = c.claim_id
            WHERE a.body ILIKE '%%880.36%%' LIMIT 1"""
    )
    row = cur.fetchone()
    print("validation (comment mentioning $880.36 -> claim approved amount):", row)
    conn.close()


if __name__ == "__main__":
    main()
