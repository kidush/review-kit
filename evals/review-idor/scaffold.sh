#!/usr/bin/env bash
# Base repo, then the change under review, committed on `feature`.
. "$(dirname "$0")/../_lib/base-repo.sh"
MSG="Let users edit invoice notes"
cat >> app/invoices.py <<'PY'


def update_note(conn, current_user_id, invoice_id, note):
    """Replace the note on one of the current user's invoices."""
    invoice = store.find_invoice(conn, invoice_id)
    if invoice is None:
        raise NotFound(invoice_id)
    conn.execute("UPDATE invoices SET note = ? WHERE id = ?", (note.strip(), invoice_id))
    return store.find_invoice(conn, invoice_id)
PY
cat >> tests/test_invoices.py <<'PY'


class UpdateNoteTest(unittest.TestCase):
    def test_owner_updates_note(self):
        conn = store.connect()
        conn.execute("INSERT INTO invoices (id, owner_id, customer, total_cents) VALUES (1, 10, 'Acme', 1000)")
        self.assertEqual(invoices.update_note(conn, 10, 1, " paid ")["note"], "paid")
PY
git add -A; git commit -qm "$MSG"
git diff main...feature > CHANGE.diff
