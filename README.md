# Security Deposit Claims

Rails app for importing, exploring, and adjudicating security-deposit claims. Source data is a spreadsheet of ~1,244 claims (`Claims.xlsx`) plus a folder of supporting claim documents — both are kept out of the repo (see `.gitignore`) because they contain tenant PII.

## The app

Ruby on Rails with PostgreSQL (`claims_app_development`). Models cover PM companies, property managers, properties, policies, leases, tenants, claims, line items, activity, adjudication decisions, and collections. Claims data is imported from the source spreadsheet via the imports workflow; claim documents are stored under `storage/documents/`.

```sh
bundle install
bin/rails db:setup
bin/rails server
```

Requires `config/master.key` (not committed).

## Not in the repo

- `Claims.xlsx` — source claims spreadsheet
- `docs/` / `docs.zip` — supporting claim documents (~2 GB)
- `storage/`, `log/` — copies of documents and logs

An earlier prototype (a Next.js frontend over a hand-built `security_deposit` Postgres DB, plus one-off Python import scripts) was removed in favor of the Rails app; it lives in the initial commit if ever needed.
