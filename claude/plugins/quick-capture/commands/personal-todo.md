---
description: Capture a todo onto the personal task board, or manage in-session memos.
argument-hint: <free text or URL> | memos | forget
---

Use the `capture-todo` skill. Behavior depends on `$ARGUMENTS`:

- **`memos`** → print the current session's `property_memo`, `enum_memo`, and `template_memo` contents as a plain-text summary. Read-only; no board calls.
- **`forget`** → clear all session memos without invalidating the schema cache. Subsequent captures re-evaluate mappings from tier 1 and re-prompt for the template.
- **anything else** → treat as capture input. Follow the skill's workflow exactly: parse input, fetch primary source + 1 hop if applicable, dedupe via the active backend adapter, resolve properties through the matching tier sequence (consulting memos first), batch any enum-miss prompts, resolve the template via override / memo / prompt (step 5.5), render the body, write through the adapter, and return the entry URL.

Template override tokens in the capture text — flag form wins, falls back to natural phrase when absent:

- `template:<name>` or `template:"<multi word name>"` → use this template for this capture and memoize it for the rest of the session.
- `no-template` → skip the template; memoized for the rest of the session.
- Natural phrasing like "use the X template" / "no template please" — only when no flag matched (confidence ≥ 0.8).

Input: $ARGUMENTS
