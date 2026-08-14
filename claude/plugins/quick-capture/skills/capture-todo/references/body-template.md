<!-- AI-drafted, 2026-06-03 -->

# Body template

Vendor-free markdown template for the body of every captured entry **when no backend template is selected**. The active backend adapter writes this content verbatim into the entry's body field.

If the workflow's step 5.5 selects a board-defined template (see [`../SKILL.md`](../SKILL.md)), this body template is **suppressed**. The selected template's `body_markdown` becomes the page body, with placeholders resolved via [`placeholders.md`](placeholders.md), followed by the AI-drafted marker line. None of the rules below apply in that case.

**Shared body-state.** The three prose fields used inside this template — the `> {context}` one-liner, the `**Why:**` line, and the `**Next:**` bullets — are computed once during workflow step 5.1 and held as shared state. The template-selected branch consumes the same `context` / `why` / `next` values via placeholders. Whichever path renders the body, the prose is derived from the same source so both paths produce equivalent content.

## Date format

The user-facing date format inside the body is read from local config at `config.locale.date_format`. Supported values:

| Config value | Example |
|---|---|
| `YYYY-MM-DD` (default, ISO) | `2026-06-03` |
| `DD.MM.YYYY` | `03.06.2026` |
| `MM/DD/YYYY` | `06/03/2026` |

The same format is used everywhere the date appears inside the body (the `captured` line, the `Source snapshot` capture-date prefix, and the in-body authorship marker).

`AI-drafted` markers in **skill source files** (this file, adapter files, the plugin README) use ISO `YYYY-MM-DD` regardless of the user's locale, because those files are repo-authored and version-controlled.

## Template

```markdown
> {one-line context with inline links on named artifacts} — captured {date}

**Why:** {motivation, 1–2 lines, with inline links where natural, or omit if not derivable}
**Next:** {next action, 1 line, with inline links where natural, or omit if not derivable}

**Source snapshot** (captured {date})
- [{title}]({source URL})
- Status: {fetched state}
- {1–2 key facts: assignees, last update, etc.}

**Related:** [{related label}]({related URL})    <!-- only when 1-hop enrichment found something -->

<!-- AI-drafted, {date} -->
```

`{date}` resolves to today's date rendered in `config.locale.date_format`.

## Rendering rules

1. **`> {one-line context}` is mandatory.** One sentence, ≤120 chars. **Inline-link any named artifact in this sentence** — if the context mentions `PR #482`, the words `PR #482` are the link to that PR. If the context mentions a Notion page by title, the title is the link.

2. **`Why` and `Next` are optional.** Include only when the input or fetched metadata gives a clear answer. If neither block is derivable, omit both — don't pad with filler. Inline-link any named artifact here too (a person, a doc, a meeting recording).

3. **`Source snapshot` block — include conditionally:**
   - Include when `Source` is `GitHub`, `GitLab`, `Notion`, `Teams`, `Linear`, or any other external source kind with state worth capturing.
   - Omit entirely for `Paper`, `Idea`, `Conversation`, `Other` — those sources have no external state to snapshot.
   - When included: 3–4 bullets max. The first bullet is the source title as an inline link to the source URL. The second bullet is `Status: {state}`. Optionally a third bullet with 1–2 supporting facts.
   - Always prefix the block header with `(captured {date})` so staleness is visible at a glance.
   - Never paste full descriptions of the source.

4. **Inline linking is the default.** Use `[label](url)` form on the words that name the artifact, inside whatever sentence or bullet they appear. Do not produce a separate `Links` block — that's been replaced by inline linking + the snapshot block + the optional `Related` line.

5. **`Related:` line — include only when 1-hop enrichment surfaced a distinct artifact.**
   - One bullet, on its own line, after the `Source snapshot` block.
   - Format: `**Related:** [<label>](<url>)`.
   - If the 1-hop target is the same artifact already linked in the snapshot title, skip — don't repeat URLs in the body.

6. **In-body authorship marker is mandatory.** Last line of the body. Format: `<!-- AI-drafted, {date} -->` with today's date. Marks the prose as machine-generated.

7. **Trim aggressively.** Total body should fit in ~12 lines for the common case. Glanceability is the goal.

8. **Never repeat the same URL twice in the body.** The primary source URL appears exactly once — either in an inline link in the context line, or as the snapshot title link, whichever reads more naturally. Not both.

## Update / extend rules

When step 4 of the workflow surfaces an existing match and the user picks **`extend`**:

- Append a horizontal rule (`---`) followed by a fresh block using this template, dated to the new capture.
- Do not overwrite the original body.
- Inline-link any new artifact references inside the new block.
- A new `**Related:**` line may follow the new block when a different 1-hop artifact surfaced this time.

When the user picks **`update`**:

- Replace the body entirely with a freshly-rendered block.
- Properties are also overwritten with newly-inferred values (except `Status`, which the user owns).
- **Caveat:** multi-select properties like `Tags` are overwritten — the freshly-inferred set replaces the existing set. If the user added manual tags between captures, they will be lost. The workflow's dedupe prompt warns about this and recommends `extend` in that case.

When the user picks **`create new`**:

- Treat as a fresh entry; the existing match is irrelevant from this point.

## Examples

`{date}` in the examples below is rendered with the default `YYYY-MM-DD` locale.

### `GitHub` source, full block

```markdown
> Review the retry-budget changes in [PR #482](https://github.com/example-org/example-repo/pull/482) before next release. — captured 2026-06-03

**Why:** PR touches the same code path that caused a past incident.
**Next:** Read PR description, leave comments on the retry-budget changes.

**Source snapshot** (captured 2026-06-03)
- [feat(retry): budget-aware backoff](https://github.com/example-org/example-repo/pull/482)
- Status: Open, awaiting review
- Assignees: 2 reviewers

**Related:** [Linked issue #441 — retry storms in ingest pipeline](https://github.com/example-org/example-repo/issues/441)

<!-- AI-drafted, 2026-06-03 -->
```

Note: `PR #482` in the context line and the snapshot title both could carry the link, but the rules say "never repeat the same URL twice". Pick one. The example shows the context-line variant — more natural for a verb-first sentence.

### `Notion` source, mention-anchor input

```markdown
> Follow up on the bug-triage automation [discussion thread](https://notion-host/page-id#block-id) raised in last week's review. — captured 2026-06-03

**Next:** Draft a 1-page proposal for the initial-assessment automation.

**Source snapshot** (captured 2026-06-03)
- [Bug triage — design notes](https://notion-host/page-id)
- Status: Open

<!-- AI-drafted, 2026-06-03 -->
```

Note: when a source has both a page URL and a block-anchor sub-URL, the context line links the anchored sub-URL (the precise mention) and the snapshot title links the page-level URL.

### `Paper` source, minimal block

```markdown
> Try a thinner ETL retry strategy — bounded by request budget rather than attempt count. — captured 2026-06-03

<!-- AI-drafted, 2026-06-03 -->
```

### `Conversation` source, with `Why` / `Next` only

```markdown
> Follow up on the quarterly planning draft. — captured 2026-06-03

**Why:** Owner asked for written feedback by end of week.
**Next:** Read the draft, send 3–5 bullets of feedback.

<!-- AI-drafted, 2026-06-03 -->
```
