#!/usr/bin/env bash
# Base repo, then the change under review, committed on `feature`.
. "$(dirname "$0")/../_lib/base-repo.sh"
MSG="Add percentage discounts"
cat >> app/invoices.py <<'PY'


def apply_discount(total_cents, percent):
    """Return the total in cents after a percentage discount."""
    if not 0 <= percent <= 100:
        raise ValueError("percent must be between 0 and 100")
    return round(total_cents * (1 - percent / 100), 2)
PY
cat >> tests/test_invoices.py <<'PY'


class DiscountTest(unittest.TestCase):
    def test_ten_percent(self):
        self.assertEqual(invoices.apply_discount(1000, 10), 900)
PY
git add -A; git commit -qm "$MSG"
git diff main...feature > CHANGE.diff
