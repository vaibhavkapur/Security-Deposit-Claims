# Security Deposit Claims

Rails app for importing, exploring, and adjudicating security-deposit claims. Source data is a spreadsheet of ~1,244 claims plus a folder of supporting claim documents (ledgers, move-out statements, invoices, SDI forms).

## How it works

The app is a three-stage pipeline, driven from the import page at the root URL:

1. **Import the spreadsheet** — upload the claims `.xlsx`; `ClaimsImport` and `CommentsImport` parse it (via roo) and normalize it into relational tables: PM companies, property managers, properties, policies, leases, tenants, claims, and claim activity.
2. **Import documents** — upload a `.zip` of claim documents; `DocumentsImport` links each file to its claim by tracking number. Extractable document types are sent to the Claude API (`DocumentExtraction`), which returns itemized charges through a forced tool call; those land in `documents.extracted_json` and are promoted into `claim_line_items` rows.
3. **Adjudicate** — enter tracking numbers on the import page. `EligibilityEngine` applies hard rules derived from historical decline reasons (duplicate claim, no identifiable policy) and proposes `min(claim amount, policy max benefit)`; evictions are approved at the cap, move-outs go to `LineItemReview`, which classifies extracted line items against coverage rules and proposes a payout. Every decision is appended to `adjudication_decisions` — nothing is overwritten, so each claim keeps a full decision history.

Claims and their documents, line items, activity, and decisions are browsable at `/claims`.

## Running it

Requires Ruby 3.2.2 and PostgreSQL.

```sh
bundle install
bin/rails db:setup
bin/rails server
```

- `ANTHROPIC_API_KEY` must be set for document extraction (stages 1 and 3 work without it).
- `config/master.key` is required and not committed.

## Not in the repo

The source data stays local because it contains tenant PII: the claims spreadsheet, the raw document folder, and `storage/` (imported document copies).
