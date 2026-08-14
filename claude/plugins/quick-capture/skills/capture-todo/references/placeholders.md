<!-- AI-drafted, 2026-06-09 -->

# Template placeholders

When a board template is selected during workflow step 5.5, its `body_markdown` may contain `{…}` text that the skill resolves and substitutes before writing the page (workflow step 6.1). This file documents the placeholder vocabulary, the resolution-tier ladder, and the substitution rules.

The substitution applies **only** on the template-selected branch. The no-template body render uses inline `[label](url)` form per [`body-template.md`](body-template.md) — placeholders are not interpreted there.

Placeholders are matched on the **prose hint** inside the braces. Templates can carry literal identifiers (`{name}`, `{date}`), curated prose phrases (`{ToDo one-liner}`, `{Why summary and/or purpose}`), or anything else. The skill walks a tier ladder to map each detected `{…}` to a logical field; if no tier hits, the brace stays literal.

## Detection

Regex `\{[^}]+\}` (open brace, one or more non-brace chars, close brace). Casing, whitespace, punctuation, slashes, commas, qualifiers like `e.g.`, and length hints like `maximum 3` are all allowed inside; the detector does not enforce snake_case. Edge cases: whitespace-only braces (`{ }`) are skipped; nested braces (`{outer {inner}}`) are not supported (regex matches to the first `}`).

Escape sequence `{{…}}` emits the inner `{…}` literally and is not resolved — use to embed sample placeholder text in a template without substitution.

## Resolution tiers

For each detected `{…}`, the skill applies these tiers in order. First hit wins.

| Tier | Name | Rule | Deterministic? |
|---|---|---|---|
| 1 | **Exact identifier** | NFC string equality against the vocabulary below. | yes |
| 2 | **Normalized identifier** | Case + whitespace fold (lowercase; runs of whitespace / slashes / hyphens → `_`; strip leading articles `the` / `a` / `an`; trim). Then exact-match the vocabulary. **Bail out** when the brace contains commas, parentheses, or dots — those signal prose and belong in tier 3. | yes |
| 3 | **Translation table** (two passes) | **Pass A:** lowercase + whitespace-collapse + trim → look up in the table below. **Pass B (on miss):** also strip parens + trailing qualifiers (see [Hint-qualifier handling](#hint-qualifier-handling)) + leading articles → re-look-up. Qualifiers stripped in B are captured for substitution time. | yes |
| 4 | **LLM-fuzzy** | LLM scores remaining candidate identifiers 0–1 on semantic closeness. Accept the top candidate only when score ≥ 0.8 AND no runner-up within 0.1 of it. | bounded |
| 5 | **Leave literal** | Brace text survives on the page; notice surfaced (see below). | n/a |

Examples:

- `{name}` → tier 1 → `name`
- `{Source}` → tier 2 → `source` · `{Due Date}` → tier 2 → `due_date` · `{related person}` → tier 2 → `related_person`
- `{ToDo one-liner}` → tier 3A → `context`
- `{Next steps following this task if available, maximum 3}` → tier 3B → `next` (captured: `if available`, `max 3`)
- `{Source, e.g. (deep) link or source name}` → tier 3A → `source_url` via the literal table entry

## Recognized vocabulary

The identifier set the resolver maps onto. Tiers 1–4 emit one of these; tier 5 surfaces a notice for anything outside it.

"Empty?" column legend:

- **always** — value is always set; the brace always substitutes.
- **literal** — empty value leaves the brace literal on the page as a hand-fill cue (default empty-fallback rule).

A conditional qualifier in the placeholder (`if available`, `(optional)`, etc.) overrides the default and substitutes empty silently instead of leaving the brace literal.

| Identifier | Substituted with | Empty? |
|---|---|---|
| `name` (alias `title`) | the resolved `Name` (todo title) | always |
| `context` | one-sentence verb-first summary from step 5.1's body-state; inline-links any named artifact | always |
| `why` | 1–2-sentence motivation from step 5.1's body-state | literal |
| `next` | 1–3 verb-first next-action bullets from step 5.1's body-state (capped at `max N` if hint carried that qualifier) | literal |
| `date` (alias `today`) | today's date in `config.locale.date_format` | always |
| `source` | `Source` kind value (e.g. `GitHub`, `Notion`, `Paper`) | literal |
| `source_url` | normalized `Source URL` | literal (`Paper` / `Idea` → no URL) |
| `source_title` | fetched source title from workflow step 2 | literal (fetch fail / skip) |
| `source_status` | fetched source state from workflow step 2 | literal (fetch fail / skip) |
| `priority` | resolved `Priority` value | always (default `Medium`) |
| `effort` | resolved `Effort` value | always (default `Medium`) |
| `tags` | comma-joined `Tags` array | literal |
| `due_date` | resolved `Due date` in `config.locale.date_format` | literal |
| `person` (alias `related_person`) | resolved `Related Person` display name; falls back to literal person/team name from input | literal |
| `related_url` | 1-hop enrichment URL from workflow step 3 | literal |
| `related_label` | 1-hop enrichment label | literal |

**Aliases collapse during detection.** When a tier records an alias identifier (`title`, `today`, `related_person`), it stores the canonical (`name`, `date`, `person`) on the triple so substitution always reads from the canonical value's state — never two parallel lookups for the same data.

## Translation table (prose → identifier)

Curated map for tier 3. Each row maps one or more common prose phrasings to a vocabulary identifier. Hand-extend by editing this file. Compare against the brace contents after lowercase + whitespace collapse + leading-article strip.

| Prose hints | Identifier |
|---|---|
| `todo one-liner`, `todo one liner`, `one liner`, `one-line context`, `title line`, `summary line` | `context` |
| `why`, `why summary`, `motivation`, `purpose`, `reason`, `why summary and/or purpose` | `why` |
| `next`, `next step`, `next steps`, `next steps following this task`, `follow-up`, `follow-ups`, `action items` | `next` |
| `person`, `team`, `person/team`, `owner`, `assignee`, `responsible` | `person` |
| `link`, `deep link`, `source link`, `source, e.g. (deep) link or source name`, `url` | `source_url` |
| `source kind`, `origin` | `source` |
| `due`, `deadline` | `due_date` |
| `priority level`, `importance` | `priority` |
| `size`, `complexity`, `effort estimate` | `effort` |
| `tag`, `label`, `theme`, `categories` | `tags` |
| `related link`, `related artifact`, `linked artifact`, `follow-up link`, `1-hop link` | `related_url` |
| `related label`, `linked label`, `follow-up label` | `related_label` |

### Hint-qualifier handling

Tier 3 pass B strips three classes of qualifiers before re-looking-up the table:

- **Length hints** (cap output): `, maximum N`, `, max N`, `(max N)`, `up to N`.
- **Conditional hints** (signal optionality): `if available`, `if known`, `if any`, `if applicable`, `(optional)`.
- **Example hints** (decoration): `, e.g. …`, `(e.g. …)`, `, like …`.

Stripped qualifiers are **captured** alongside the identifier and re-applied at substitution time regardless of which tier produced the identifier:

- A **length hint** caps the rendered output. Caps apply only to list-typed identifiers (`next` — bullets, joined with `\n`; `tags` — comma-joined). For scalars (`name`, `priority`, `context`, `why`, `source_url`, etc.) the cap is ignored. `{Next steps, maximum 3}` is trimmed to at most 3 bullets even if the `next` body-state has more; `{Tags, max 2}` substitutes the first two tags; `{Why, max 1}` substitutes the full single-line `why` value (cap ignored).
- A **conditional hint** suppresses the hand-fill notice on empty values. `{Why summary if available}` with empty `why` state substitutes as an empty string and does **not** add to the `Left N placeholder(s) literal for hand-fill` list — the template author has explicitly marked the slot as optional.
- An **example hint** is discarded after the lookup; it only existed to help the human reader of the template understand the slot.

Without a conditional hint, the default empty-fallback rule (leave brace literal as hand-fill cue) applies. Tiers 1 and 2 never see qualifier-bearing braces, so qualifier handling lives entirely in tier 3 pass B + substitution time.

## Substitution algorithm

1. Take the template's `body_markdown` as the working buffer.
2. **Backslash-unescape pass:** replace `\{` → `{` and `\}` → `}` across the buffer. Notion's MCP serializes literal braces as backslash-escaped, so `{X}` arrives as `\{X\}`. Idempotent on bodies that already use plain braces.
3. **Escape pass:** replace every `{{…}}` escape sequence with a sentinel (e.g. `\x00ESC:…\x00`) so it survives all later passes.
4. **Detection pass:** for every `{…}` match remaining in the buffer (skip matches whose contents are whitespace-only — they survive verbatim and never enter the tier ladder):
   - Apply tier 1 (exact identifier). On hit, record `(brace, identifier, qualifiers={})`.
   - Else apply tier 2 (normalized identifier; bail out if brace contains commas / parens / dots). On hit, record the triple.
   - Else apply tier 3 (translation table, two-pass; pass B captures stripped qualifiers). On hit, record the triple.
   - Else apply tier 4 (LLM-fuzzy ≥ 0.8 + 0.1 margin) over the vocabulary. On hit, record the triple. Qualifiers captured during tier 3 pass B (if it ran) carry forward; otherwise none are captured.
   - Else mark the brace as **unrecognized** and leave it for tier 5 (literal).
5. **Substitution pass:** for each `(brace, identifier, qualifiers)` triple:
   - Resolve the identifier to its current value from the in-memory state built by workflow steps 5.1–5.5 (the write payload plus the inferred `context`, `why`, `next` lines).
   - **If the resolved value is present:** replace the brace with the value, applying any captured length qualifier (e.g. trim `next` to `max N` bullets).
   - **If the resolved value is empty AND `qualifiers` contains a conditional hint:** replace the brace with an empty string. Do **not** add to the hand-fill notice — the template author marked the slot optional.
   - **If the resolved value is empty AND no conditional hint:** leave the brace literal (default empty-fallback rule) and add it to the `empty_placeholders` notice list.
6. **Restore pass:** replace sentinels back to literal `{…}`.
7. Append the AI-drafted marker as the last line of the body.

Result is written verbatim by the adapter's `create_entry`.

## Notices surfaced to the user

After step 6.1 runs, the response includes (in this order, each line omitted when its count is zero):

1. `Using your "<template name>" template.` (from step 5.5).
2. `Filled <N> placeholder(s).` — count of substitutions.
3. `Left <N> placeholder(s) literal for hand-fill: {Due date}, {Why summary…}.` — recognized identifiers with empty values (no conditional qualifier). Example list capped at 5.
4. `Left <N> unrecognized placeholder(s) literal: {SomeCustomThing}.` — tier-5 fall-throughs. Cap at 5.

A template with zero detected braces produces no extra notice.

## Anti-patterns

- **Don't substitute past tier 4's confidence threshold.** When the LLM is uncertain (top score < 0.8 or runner-up within 0.1), leaving the brace literal is safer than writing the wrong value.
- **Don't add per-user entries to the translation table.** This file ships with the skill. User-specific prose-to-identifier maps resurrect the persisted-translation-layer pattern.
- **Don't do arbitrary expression evaluation inside braces.** No `{date+7}`, no `{tags | join(",")}`, no `{user.email}`. Static lookups against the recognized vocabulary only.
- **Don't auto-fill empty values with fabricated content.** An empty `{Why}` stays as `{Why}` (or substitutes empty when a conditional hint marked it optional), never as an invented reason.
- **Don't surface hand-fill notices for optional placeholders.** Conditional qualifiers (`if available`, `if known`, `if applicable`, `if any`, `(optional)`) suppress the notice on empty values — the template author already said the slot is dispensable.
