import Link from "next/link";
import pool from "@/lib/db";

export const dynamic = "force-dynamic";

function money(v: string | null) {
  if (v === null) return "—";
  return Number(v).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

function badgeClass(status: string | null) {
  const s = (status ?? "").toLowerCase();
  if (s.includes("declin")) return "badge declined";
  if (s.includes("hold") || s.includes("pending")) return "badge hold";
  if (s.includes("posted") || s.includes("approved")) return "badge posted";
  return "badge";
}

export default async function ClaimsPage() {
  const { rows } = await pool.query(`
    SELECT c.claim_id, c.tracking_number, c.claim_date, c.status,
           c.termination_type, c.claim_amount, c.approved_benefit_amount,
           count(a.activity_id)::int AS activity_count
      FROM claims c
      LEFT JOIN claim_activity a ON a.claim_id = c.claim_id
     GROUP BY c.claim_id
     ORDER BY count(a.activity_id) DESC, c.tracking_number::int
  `);
  const { rows: unlinked } = await pool.query(
    `SELECT count(*)::int AS n, count(DISTINCT source_row_ref)::int AS threads
       FROM claim_activity WHERE claim_id IS NULL`
  );

  return (
    <main>
      <h1>Security Deposit Claims</h1>
      <p className="subtitle">
        {rows.length} claims imported from Claims.xlsx.{" "}
        <Link href="/activity/unlinked">
          {unlinked[0].threads} activity threads ({unlinked[0].n} comments) not
          yet linked to a claim
        </Link>
        .
      </p>
      <table>
        <thead>
          <tr>
            <th>Tracking #</th>
            <th>Claim Date</th>
            <th>Status</th>
            <th>Termination</th>
            <th className="num">Claim Amount</th>
            <th className="num">Approved</th>
            <th className="num">Activity</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((c) => (
            <tr key={c.claim_id}>
              <td>
                <Link href={`/claims/${c.claim_id}`}>{c.tracking_number}</Link>
              </td>
              <td>
                {c.claim_date
                  ? new Date(c.claim_date).toISOString().slice(0, 10)
                  : "—"}
              </td>
              <td>
                <span className={badgeClass(c.status)}>{c.status ?? "—"}</span>
              </td>
              <td>{c.termination_type ?? "—"}</td>
              <td className="num">{money(c.claim_amount)}</td>
              <td className="num">{money(c.approved_benefit_amount)}</td>
              <td className="num">{c.activity_count || "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
