import Link from "next/link";
import { notFound } from "next/navigation";
import pool from "@/lib/db";

export const dynamic = "force-dynamic";

function money(v: string | null) {
  if (v === null) return "—";
  return Number(v).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

function fmtDate(v: unknown) {
  if (!v) return "—";
  return v instanceof Date ? v.toISOString().slice(0, 10) : String(v).slice(0, 10);
}

const LINK_METHOD_LABEL: Record<string, string> = {
  explicit_ref: "linked via explicit #tracking reference in comments",
  address: "linked via unique street address match",
  approval_amount: "linked via unique approval amount match",
  tenant_name: "linked via tenant name from claim documents",
};

export default async function ClaimPage({
  params,
}: {
  params: { id: string };
}) {
  const id = Number(params.id);
  if (!Number.isInteger(id)) notFound();

  const { rows } = await pool.query(
    `SELECT * FROM claims WHERE claim_id = $1`,
    [id]
  );
  if (rows.length === 0) notFound();
  const c = rows[0];

  const { rows: activity } = await pool.query(
    `SELECT author, body, created_at, link_method
       FROM claim_activity
      WHERE claim_id = $1
      ORDER BY created_at ASC`,
    [id]
  );
  const linkMethod: string | undefined = activity[0]?.link_method;

  return (
    <main>
      <p className="backlink">
        <Link href="/">← All claims</Link>
      </p>
      <h1>Claim #{c.tracking_number}</h1>
      <p className="subtitle">
        {c.status ?? "No status"}
        {c.termination_type ? ` · ${c.termination_type}` : ""}
      </p>

      <dl className="facts">
        <div>
          <dt>Claim Date</dt>
          <dd>{fmtDate(c.claim_date)}</dd>
        </div>
        <div>
          <dt>Claim Amount</dt>
          <dd>{money(c.claim_amount)}</dd>
        </div>
        <div>
          <dt>Approved Amount</dt>
          <dd>{money(c.approved_benefit_amount)}</dd>
        </div>
        <div>
          <dt>Approval Date</dt>
          <dd>{fmtDate(c.approval_date)}</dd>
        </div>
        <div>
          <dt>Posted Date</dt>
          <dd>{fmtDate(c.posted_date)}</dd>
        </div>
        <div>
          <dt>Collections Opened</dt>
          <dd>
            {c.collections_opened === null
              ? "—"
              : c.collections_opened
                ? "Yes"
                : "No"}
          </dd>
        </div>
      </dl>

      {c.pm_explanation && (
        <p>
          <strong>PM Explanation:</strong> {c.pm_explanation}
        </p>
      )}
      {c.hold_reason && (
        <p>
          <strong>Hold Reason:</strong> {c.hold_reason}
        </p>
      )}

      <div className="section">
        <h2>Activity ({activity.length})</h2>
        {activity.length === 0 ? (
          <p className="linknote">
            No activity linked to this claim yet. Comment threads from the
            spreadsheet could not be positionally matched (the sheet was
            re-sorted after export); only content-verified links are shown.
          </p>
        ) : (
          <>
            {linkMethod && (
              <p className="linknote">
                {LINK_METHOD_LABEL[linkMethod] ?? linkMethod}
              </p>
            )}
            {activity.map((a, i) => (
              <div className="comment" key={i}>
                <div className="meta">
                  <span className="author">{a.author}</span>
                  <span>{new Date(a.created_at).toLocaleString("en-US")}</span>
                </div>
                <div className="body">{a.body}</div>
              </div>
            ))}
          </>
        )}
      </div>
    </main>
  );
}
