#!/usr/bin/env bash
# Sourced by each case's scaffold.sh: builds a small invoicing repo in the current directory,
# committed on `main`, then checks out `feature` for the case to add its change.
set -euo pipefail
git init -q -b main
git config user.email bench@local; git config user.name bench
mkdir -p app tests
cat > app/__init__.py <<'PY'
PY
cat > app/errors.py <<'PY'
class NotFound(Exception):
    pass
PY
cat > app/store.py <<'PY'
import sqlite3


def connect(path=":memory:"):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute(
        "CREATE TABLE IF NOT EXISTS invoices ("
        "id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, customer TEXT NOT NULL, "
        "total_cents INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '')"
    )
    return conn


def find_invoice(conn, invoice_id):
    return conn.execute("SELECT * FROM invoices WHERE id = ?", (invoice_id,)).fetchone()


def invoices_for_owner(conn, owner_id):
    return conn.execute(
        "SELECT * FROM invoices WHERE owner_id = ? ORDER BY id", (owner_id,)
    ).fetchall()
PY
cat > app/invoices.py <<'PY'
from app import store
from app.errors import NotFound


def get_invoice(conn, current_user_id, invoice_id):
    """Return the invoice if it exists and belongs to the current user."""
    invoice = store.find_invoice(conn, invoice_id)
    if invoice is None or invoice["owner_id"] != current_user_id:
        raise NotFound(invoice_id)
    return invoice


def split_cents(total_cents, parts):
    """Split an amount in integer cents into `parts` installments that add up to the total."""
    if parts < 1:
        raise ValueError("parts must be at least 1")
    base, remainder = divmod(total_cents, parts)
    return [base + 1 if i < remainder else base for i in range(parts)]
PY
cat > tests/__init__.py <<'PY'
PY
cat > tests/test_invoices.py <<'PY'
import unittest

from app import invoices, store
from app.errors import NotFound


class InvoicesTest(unittest.TestCase):
    def setUp(self):
        self.conn = store.connect()
        self.conn.execute(
            "INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'Acme', 1000)"
        )

    def test_owner_gets_invoice(self):
        self.assertEqual(invoices.get_invoice(self.conn, 10, 1)["customer"], "Acme")

    def test_other_user_gets_not_found(self):
        with self.assertRaises(NotFound):
            invoices.get_invoice(self.conn, 99, 1)

    def test_split_cents_adds_up(self):
        self.assertEqual(invoices.split_cents(1000, 3), [334, 333, 333])
PY
cat > tests/test_store.py <<'PY'
import unittest

from app import store


class StoreTest(unittest.TestCase):
    def test_invoices_for_owner(self):
        conn = store.connect()
        conn.execute("INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'Acme', 5)")
        self.assertEqual([r["id"] for r in store.invoices_for_owner(conn, 10)], [1])
PY
cat > .review-gate.sh <<'SH'
BASE="main"
SRC_PATTERN='^app/.*\.py$'
SRC_EXCLUDE_PATTERN='(^|/)__init__\.py$'
test_pattern_for() { printf '^tests/test_%s\\.py$' "$(basename "$1" .py)"; }
TEST_CMD="python3 -m unittest discover -s tests -t ."
SH
cat > REVIEW.md <<'MD'
# Review notes

- Money is integer cents everywhere. Never use floats for amounts.
- Every function that takes `current_user_id` must check ownership before reading or changing an invoice.
- SQL uses `?` placeholders only; never build SQL from input.
MD
git add -A; git commit -qm "Invoicing base"
git checkout -qb feature
