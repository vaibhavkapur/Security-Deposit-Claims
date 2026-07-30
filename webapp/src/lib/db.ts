import { Pool, types } from "pg";

// Return DATE columns as plain "YYYY-MM-DD" strings; the default Date-object
// parsing shifts dates across the UTC boundary.
types.setTypeParser(types.builtins.DATE, (v) => v);

const pool = new Pool({
  connectionString:
    process.env.DATABASE_URL ?? "postgresql://localhost/security_deposit",
});

export default pool;
