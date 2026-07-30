"""Final content-based linking of comment threads to claims.

Methods, in precedence order (all require an unambiguous single-claim match):
  1. explicit_ref     - "#546" / "tracking #212" style references in the text
  2. address          - unique "number streetname" from the sheet found in text
  3. approval_amount  - "approv... $X" where X (with cents) matches exactly one
                        claim's approved_benefit_amount
  4. tenant_name      - proper-noun surname from a docs folder's filenames,
                        capitalized in the comment, absent from the system
                        dictionary, mapping to exactly one folder
Cross-method conflicts leave the thread unlinked.
"""
import os
import re
from collections import defaultdict

import pandas as pd
import psycopg2

XLSX = "Claims.xlsx"
DICT_WORDS = {
    w.strip().lower() for w in open("/usr/share/dict/words", encoding="utf-8")
}
DOC_STOPWORDS = {
    "lease", "ledger", "statement", "letter", "closeout", "summary", "invoice",
    "notice", "deposit", "security", "claim", "addendum", "final", "signed",
    "docusign", "moveout", "makeready", "propertyware", "appfolio", "buildium",
}


def build_blobs(com):
    blobs = defaultdict(list)
    for _, r in com.iterrows():
        blobs[r["row_n"]].append(str(r["body"]))
    return {n: " ".join(b) for n, b in blobs.items()}


def explicit_refs(blobs, valid_tn):
    pat = re.compile(r"(?<![\w])#\s?(\d{1,4})\b")
    out = {}
    for n, blob in blobs.items():
        cand = set()
        for m in pat.finditer(blob):
            ctx = blob[max(0, m.start() - 20):m.start()].lower()
            if any(w in ctx for w in ["unit", "apt", "apartment", "phone",
                                      "account", "acct", "check", "cheque", "invoice"]):
                continue
            v = int(m.group(1))
            if v in valid_tn and v > 3:
                cand.add(v)
        if len(cand) == 1:
            out[n] = cand.pop()
    return out


def address_anchors(main_df, blobs):
    df = main_df.copy()
    df["addr_key"] = df["Lease Street Address"].astype(str).str.extract(
        r"^(\d+\s+\w{4,})", expand=False
    )
    counts = df["addr_key"].value_counts()
    unique = {k for k in counts[counts == 1].index if isinstance(k, str)}
    tn_by_key = {k: int(t) for k, t in zip(df["addr_key"], df["tn"]) if k in unique}
    out = {}
    for n, blob in blobs.items():
        low = blob.lower()
        hits = {tn_by_key[k] for k in unique if k.lower() in low}
        if len(hits) == 1:
            out[n] = hits.pop()
    return out


def approval_amount_anchors(main_df, blobs):
    approved = pd.to_numeric(main_df["Approved Benefit Amount"], errors="coerce")
    counts = approved.value_counts()
    unique_amts = {
        round(a, 2): int(t)
        for a, t in zip(approved, main_df["tn"])
        if counts.get(a, 0) == 1 and a and a % 1 != 0  # cents-bearing, unique
    }
    pat = re.compile(r"approv\w*[^.]{0,40}?\$?([\d,]+\.\d{2})", re.I)
    out = {}
    for n, blob in blobs.items():
        hits = set()
        for m in pat.finditer(blob):
            amt = round(float(m.group(1).replace(",", "")), 2)
            if amt in unique_amts:
                hits.add(unique_amts[amt])
        if len(hits) == 1:
            out[n] = hits.pop()
    return out


def tenant_name_anchors(blobs):
    token_to_folders = defaultdict(set)
    for folder in os.listdir("docs"):
        if not folder.isdigit():
            continue
        for fn in os.listdir(os.path.join("docs", folder)):
            for tok in re.findall(r"[A-Za-z]{5,}", fn):
                t = tok.lower()
                if t not in DOC_STOPWORDS and t not in DICT_WORDS:
                    token_to_folders[t].add(int(folder))
    unique = {t: f.pop() for t, f in token_to_folders.items() if len(f) == 1}
    out = {}
    for n, blob in blobs.items():
        # proper-noun usage in the comment (capitalized, not sentence-start-only heuristic)
        caps = {w.lower() for w in re.findall(r"(?<=[a-z,;\s])([A-Z][a-z]{4,})", blob)}
        hits = {unique[w] for w in caps if w in unique}
        if len(hits) == 1:
            out[n] = hits.pop()
    return out


def main():
    xl = pd.ExcelFile(XLSX)
    main_df = xl.parse("Security Deposit Claims")
    main_df = main_df[main_df["Tracking Number"].notna()].reset_index(drop=True)
    main_df["tn"] = main_df["Tracking Number"].astype(int)
    valid_tn = set(main_df["tn"])

    com = xl.parse("Comments", header=None)
    com.columns = ["row_ref", "body", "author", "ts"]
    com = com[com["row_ref"].astype(str).str.match(r"Row \d+")].copy()
    com["row_n"] = (
        com["row_ref"].astype(str).str.replace("Row", "", regex=False).str.strip().astype(int)
    )
    blobs = build_blobs(com)

    methods = {
        "explicit_ref": explicit_refs(blobs, valid_tn),
        "address": address_anchors(main_df, blobs),
        "approval_amount": approval_amount_anchors(main_df, blobs),
        "tenant_name": tenant_name_anchors(blobs),
    }
    for name, m in methods.items():
        print(f"{name}: {len(m)} threads")

    # cross-method agreement report
    names = list(methods)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = methods[names[i]], methods[names[j]]
            both = set(a) & set(b)
            agree = sum(a[n] == b[n] for n in both)
            if both:
                print(f"  {names[i]} vs {names[j]}: overlap={len(both)}, agree={agree}")

    # resolve with precedence; conflict -> unlinked
    link = {}
    conflicts = set()
    for name in ["explicit_ref", "address", "approval_amount", "tenant_name"]:
        for n, t in methods[name].items():
            if n in conflicts:
                continue
            if n in link and link[n][0] != t:
                conflicts.add(n)
                del link[n]
            elif n not in link:
                link[n] = (t, name)
    print(f"linked threads: {len(link)}, conflicts (unlinked): {len(conflicts)}")

    conn = psycopg2.connect("dbname=security_deposit")
    cur = conn.cursor()
    cur.execute("SELECT tracking_number, claim_id FROM claims")
    cid = {int(t): c for t, c in cur.fetchall()}
    cur.execute("UPDATE claim_activity SET claim_id = NULL, link_method = NULL")
    updated = 0
    for n, (t, method) in link.items():
        cur.execute(
            "UPDATE claim_activity SET claim_id=%s, link_method=%s WHERE source_row_ref=%s",
            (cid[t], method, f"Row {n}"),
        )
        updated += cur.rowcount
    conn.commit()
    cur.execute("SELECT link_method, count(*) FROM claim_activity GROUP BY 1 ORDER BY 2 DESC")
    print("comment rows by link method:", cur.fetchall())
    cur.execute("SELECT count(DISTINCT claim_id) FROM claim_activity WHERE claim_id IS NOT NULL")
    print("claims with linked activity:", cur.fetchone()[0])
    conn.close()


if __name__ == "__main__":
    main()
