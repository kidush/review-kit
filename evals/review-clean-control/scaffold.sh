#!/usr/bin/env bash
# Base repo, then the change under review, committed on `feature`.
. "$(dirname "$0")/../_lib/base-repo.sh"
MSG="Add per-owner invoice totals"
cat >> app/store.py <<'PY'


def total_cents_for_owner(conn, owner_id):
    """Sum of total_cents over the owner's invoices; 0 when the owner has none."""
    row = conn.execute(
        "SELECT COALESCE(SUM(total_cents), 0) AS total FROM invoices WHERE owner_id = ?",
        (owner_id,),
    ).fetchone()
    return row["total"]
PY
cat >> tests/test_store.py <<'PY'


class TotalTest(unittest.TestCase):
    def setUp(self):
        self.conn = store.connect()
        self.conn.executemany(
            "INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (?, ?, ?, ?)",
            [(1, 10, "Acme", 500), (2, 10, "Beta", 250), (3, 20, "Acme", 999)],
        )

    def test_sums_only_the_owners_invoices(self):
        self.assertEqual(store.total_cents_for_owner(self.conn, 10), 750)

    def test_owner_without_invoices_is_zero(self):
        self.assertEqual(store.total_cents_for_owner(self.conn, 30), 0)
PY
git add -A; git commit -qm "$MSG"
git diff main...feature > CHANGE.diff
