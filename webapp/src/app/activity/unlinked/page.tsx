import Link from "next/link";
import pool from "@/lib/db";

export const dynamic = "force-dynamic";

export default async function UnlinkedActivityPage({
  searchParams,
}: {
  searchParams: { page?: string };
}) {
  const page = Math.max(1, Number(searchParams.page) || 1);
  const perPage = 25;

  const { rows: threads } = await pool.query(
    `SELECT source_row_ref,
            count(*)::int AS n,
            min(created_at) AS first_at,
            max(created_at) AS last_at
       FROM claim_activity
      WHERE claim_id IS NULL AND source_row_ref IS NOT NULL
      GROUP BY source_row_ref
      ORDER BY max(created_at) DESC
      LIMIT $1 OFFSET $2`,
    [perPage, (page - 1) * perPage]
  );
  const refs = threads.map((t) => t.source_row_ref);
  const { rows: comments } = await pool.query(
    `SELECT source_row_ref, author, body, created_at
       FROM claim_activity
      WHERE source_row_ref = ANY($1)
      ORDER BY created_at ASC`,
    [refs]
  );
  const byRef = new Map<string, typeof comments>();
  for (const c of comments) {
    const list = byRef.get(c.source_row_ref) ?? [];
    list.push(c);
    byRef.set(c.source_row_ref, list);
  }
  const { rows: total } = await pool.query(
    `SELECT count(DISTINCT source_row_ref)::int AS n
       FROM claim_activity WHERE claim_id IS NULL AND source_row_ref IS NOT NULL`
  );
  const pages = Math.ceil(total[0].n / perPage);

  return (
    <main>
      <p className="backlink">
        <Link href="/">← All claims</Link>
      </p>
      <h1>Unlinked activity threads</h1>
      <p className="subtitle">
        {total[0].n} comment threads reference spreadsheet rows that cannot be
        positionally trusted (the sheet was re-sorted after export). Each is
        kept grouped by its original row reference until it can be linked to a
        claim by content.
      </p>

      {threads.map((t) => (
        <div className="section" key={t.source_row_ref}>
          <h3>
            {t.source_row_ref} · {t.n} comment{t.n === 1 ? "" : "s"}
          </h3>
          {(byRef.get(t.source_row_ref) ?? []).map((c, i) => (
            <div className="comment" key={i}>
              <div className="meta">
                <span className="author">{c.author}</span>
                <span>{new Date(c.created_at).toLocaleString("en-US")}</span>
              </div>
              <div className="body">{c.body}</div>
            </div>
          ))}
        </div>
      ))}

      <p className="section">
        {page > 1 && (
          <Link href={`/activity/unlinked?page=${page - 1}`}>← Newer</Link>
        )}{" "}
        Page {page} of {pages}{" "}
        {page < pages && (
          <Link href={`/activity/unlinked?page=${page + 1}`}>Older →</Link>
        )}
      </p>
    </main>
  );
}
