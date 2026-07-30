"""Import the Comments tab into claim_activity with content-based claim linking.

The Comments tab references claims by sheet position ("Row N"), but the first
tab was re-sorted after export, so positions are unreliable (verified: stated
approval amounts land on the wrong claims). Instead, each comment thread is
linked to a claim only when its content unambiguously matches:
  - the claim's street address (from the sheet), or
  - tenant/address tokens from the claim's docs folder filenames
Threads with no unambiguous match stay unlinked (claim_id NULL) but keep their
source_row_ref so the thread grouping survives.
"""
import os
import re
from collections import defaultdict
from datetime import datetime

import pandas as pd
import psycopg2

DB = "dbname=security_deposit"
DOC_STOPWORDS = {
    "lease", "ledger", "move", "out", "statement", "letter", "close", "closeout",
    "summary", "invoice", "notice", "deposit", "security", "claim", "addendum",
    "sdi", "final", "copy", "page", "docs", "file", "form", "signed", "fully",
    "executed", "agreement", "renewal", "application", "itemization", "itemized",
    "disposition", "damages", "damage", "photos", "photo", "estimate", "receipt",
    "moveout", "charges", "account", "resident", "tenant", "unit", "apt", "street",
    "avenue", "drive", "court", "lane", "road", "circle", "place", "north", "south",
    "east", "west",
}


def thread_blobs(com):
    """Group comments by Row N -> single lowercase text blob."""
    blobs = defaultdict(list)
    for _, r in com.iterrows():
        blobs[r["row_n"]].append(str(r["body"]))
    return {n: " || ".join(b).lower() for n, b in blobs.items()}


def address_anchors(main_df, blobs):
    """Row N -> tracking via unique 'number streetname' appearing in thread."""
    main_df = main_df.copy()
    main_df["addr_key"] = (
        main_df["Lease Street Address"].astype(str).str.extract(r"^(\d+\s+\w{4,})", expand=False)
    )
    counts = main_df["addr_key"].value_counts()
    unique_keys = {k for k in counts[counts == 1].index if isinstance(k, str)}
    tn_by_key = {
        k: int(t)
        for k, t in zip(main_df["addr_key"], main_df["tn"])
        if k in unique_keys
    }
    out = {}
    for n, blob in blobs.items():
        hits = {tn_by_key[k] for k in unique_keys if k.lower() in blob}
        if len(hits) == 1:
            out[n] = hits.pop()
    return out


def docs_anchors(blobs):
    """Row N -> tracking via distinctive tokens from docs folder filenames."""
    token_to_folders = defaultdict(set)
    docs = "docs"
    for folder in os.listdir(docs):
        if not folder.isdigit():
            continue
        for fn in os.listdir(os.path.join(docs, folder)):
            for tok in re.findall(r"[A-Za-z]{5,}", fn):
                t = tok.lower()
                if t not in DOC_STOPWORDS:
                    token_to_folders[t].add(int(folder))
    unique_tokens = {t: f.pop() for t, f in token_to_folders.items() if len(f) == 1}
    out = {}
    for n, blob in blobs.items():
        words = set(re.findall(r"[a-z]{5,}", blob))
        hits = {unique_tokens[w] for w in words if w in unique_tokens}
        if len(hits) == 1:
            out[n] = hits.pop()
    return out


def main():
    xl = pd.ExcelFile("Claims.xlsx")
    main_df = xl.parse("Security Deposit Claims")
    main_df = main_df[main_df["Tracking Number"].notna()].reset_index(drop=True)
    main_df["tn"] = main_df["Tracking Number"].astype(int)

    com = xl.parse("Comments", header=None)
    com.columns = ["row_ref", "body", "author", "ts"]
    com["row_ref"] = com["row_ref"].astype(str)
    has_row = com["row_ref"].str.match(r"Row \d+")
    com.loc[has_row, "row_n"] = (
        com.loc[has_row, "row_ref"].str.replace("Row", "", regex=False).str.strip().astype(int)
    )

    blobs = thread_blobs(com[has_row])
    addr = address_anchors(main_df, blobs)
    docs = docs_anchors(blobs)

    both = set(addr) & set(docs)
    agree = {n for n in both if addr[n] == docs[n]}
    conflict = both - agree
    print(f"threads: {len(blobs)} | addr-linked: {len(addr)} | docs-linked: {len(docs)}")
    print(f"overlap: {len(both)}, agree: {len(agree)}, conflict: {len(conflict)}")

    link = {}
    for n, t in addr.items():
        if n not in conflict:
            link[n] = (t, "address" if n not in agree else "address+docs")
    for n, t in docs.items():
        if n not in link and n not in conflict:
            link[n] = (t, "docs_filename")

    conn = psycopg2.connect(DB)
    cur = conn.cursor()
    cur.execute("SELECT tracking_number, claim_id FROM claims")
    claim_id_by_tn = {int(tn): cid for tn, cid in cur.fetchall()}

    inserted = linked = 0
    for _, r in com.iterrows():
        row_n = r.get("row_n")
        row_n = int(row_n) if pd.notna(row_n) else None
        claim_id, method = (None, None)
        if row_n in link:
            tn, method = link[row_n]
            claim_id = claim_id_by_tn.get(tn)
        try:
            ts = datetime.strptime(str(r["ts"]).strip(), "%m/%d/%y %I:%M %p")
        except ValueError:
            continue
        cur.execute(
            """INSERT INTO claim_activity
                 (claim_id, author, body, created_at, source_row_ref, link_method)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            (
                claim_id,
                str(r["author"]) if pd.notna(r["author"]) else "unknown",
                str(r["body"]),
                ts,
                r["row_ref"] if r["row_ref"] != "nan" else None,
                method,
            ),
        )
        inserted += 1
        linked += claim_id is not None
    conn.commit()
    print(f"inserted {inserted} comments, {linked} linked to a claim")
    cur.execute(
        "SELECT link_method, count(*) FROM claim_activity GROUP BY link_method ORDER BY 2 DESC"
    )
    print(cur.fetchall())
    conn.close()


if __name__ == "__main__":
    main()
