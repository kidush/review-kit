#!/usr/bin/env bash
# Base repo, then the change under review, committed on `feature`.
. "$(dirname "$0")/../_lib/base-repo.sh"
MSG="Search a user's invoices by customer"
cat >> app/store.py <<'PY'


def search_by_customer(conn, owner_id, term):
    """Invoices of `owner_id` whose customer name contains `term`."""
    return conn.execute(
        f"SELECT * FROM invoices WHERE owner_id = ? AND customer LIKE '%{term}%' ORDER BY id",
        (owner_id,),
    ).fetchall()
PY
cat >> tests/test_store.py <<'PY'


class SearchTest(unittest.TestCase):
    def test_search_by_customer(self):
        conn = store.connect()
        conn.execute("INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'Acme', 5)")
        self.assertEqual([r["id"] for r in store.search_by_customer(conn, 10, "cm")], [1])
PY
git add -A; git commit -qm "$MSG"
git diff main...feature > CHANGE.diff
