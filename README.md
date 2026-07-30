# Security Deposit Claims

Tools for importing, exploring, and adjudicating security-deposit claims. Source data is a spreadsheet of ~1,244 claims (`Claims.xlsx`) plus a folder of supporting claim documents — both are kept out of the repo (see `.gitignore`) because they contain tenant PII.

## What's here

- **`claims_app/`** — Ruby on Rails app (PostgreSQL) that holds the normalized claims database and adjudication workflow. Models cover PM companies, property managers, properties, policies, leases, tenants, claims, line items, activity, adjudication decisions, and collections. Run with `bin/rails server` after `bundle install` and `bin/rails db:setup`. Requires `config/master.key` (not committed).
- **`webapp/`** — Next.js/TypeScript front end for browsing claims and activity. Run with `npm install && npm run dev`.
- **`db-schema.md`** — Database schema derived from the source spreadsheet, with an ER diagram and import order.
- **`import_activity.py`, `link_activity.py`, `link_activity2.py`** — One-off Python scripts for importing claim activity data and linking it to claims.

## Not in the repo

- `Claims.xlsx` — source claims spreadsheet
- `docs/` / `docs.zip` — supporting claim documents (~2 GB)
- `claims_app/storage/`, `claims_app/log/` — copies of documents and logs
