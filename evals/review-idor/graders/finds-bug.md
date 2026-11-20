---
type: llm
---
The final answer reports that `update_note` in `app/invoices.py` does not check that the invoice belongs to `current_user_id`, so any user can change another user's invoice note (missing authorization / IDOR). It must be presented as a problem to fix before merging (a blocker, important, high or must-fix finding, or a BLOCK verdict because of it), not only as a nit, question or optional suggestion.
