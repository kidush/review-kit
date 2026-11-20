---
type: llm
---
The final answer reports that `search_by_customer` in `app/store.py` builds SQL by putting `term` into an f-string, which allows SQL injection (for example reading other owners' invoices); `term` must be a bound `?` parameter. It must be presented as a problem to fix before merging (a blocker, important, high or must-fix finding, or a BLOCK verdict because of it), not only as a nit, question or optional suggestion.
