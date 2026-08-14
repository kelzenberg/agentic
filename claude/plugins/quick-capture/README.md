<!-- AI-drafted, 2026-06-09 -->

# quick-capture

Capture todos onto a personal task board from any input — URLs, mentions, free text, paper notes — with structured properties and a concise body of deep links. Backend-agnostic by design.

## What it ships

- **[`capture-todo`](skills/capture-todo/SKILL.md)** — the capture skill. Auto-activates on phrases like "add to my todos", "capture this", "track this", "follow up on…", "remind me to…", "park this", or when the user pastes a GitHub / GitLab / Notion / Teams / Linear URL with capture intent.
- **[`/personal-todo`](commands/personal-todo.md)** — explicit slash command. `/personal-todo <free text or URL>` invokes the skill regardless of phrasing.

## Privacy & portability

This repo holds **no user-specific data**. No board URLs, no workspace names, no database IDs, no personal handles. The skill works for any user with a Notion (or other supported) board; everyone keeps their own board location in a local config file outside this repo:

- **`~/.config/quick-capture/config.json`** — created by the skill on first run, lives outside any git repo, single-user (file mode `600` on Unix; default user-profile ACLs on Windows).

The local config has exactly three fields:

```json
{
  "active_backend": "notion",
  "board_ref": "<full URL of your board>",
  "locale": { "date_format": "YYYY-MM-DD" }
}
```

Nothing else is persisted to disk. No property names, no tag enumeration, no template inventory, no version stamp. The skill rediscovers the board's schema at the start of every session and holds it in memory for the duration of that conversation (no disk write). A new conversation refetches.

## Source surface is read-only

The skill never writes anything back to the source surface. No comments on Notion pages, no comments on GitHub / GitLab issues. The source URL only appears inside the todo body (inline link in the context line, or snapshot title link). The trail is one-way: todo → source. Source readers see no trace of personal tracking.

## Board templates

If you have page templates defined on your board (e.g. a bug-triage template, a follow-up template), the skill discovers them at session start and uses them when creating new todos. The template body is canonical — the skill does not inject its own context lines or snapshot blocks into a template-shaped page; it only substitutes placeholders and appends the AI-drafted marker. Template property defaults (e.g. a pre-set `Effort` or `Tags`) fill gaps the skill couldn't infer from input; explicit input signals still win.

The skill asks which template to use the first time templates exist on the board in a session — it never presumes you want one for every capture. The picker includes a `No template — render the skill body` escape option. Your choice is remembered for the rest of the session; override per capture by including `template:<name>` or `no-template` in your capture text.

### Template placeholders

Templates can carry `{placeholder}` text that the skill substitutes with inferred values before writing the page — e.g. `{title}`, `{source_url}`, `{date}`, `{priority}`, `{tags}`. See [`placeholders.md`](skills/capture-todo/references/placeholders.md) for the recognized set. Unknown `{names}` are left literal so code samples and other intentional `{x}` content survive unchanged. Use `{{name}}` to escape a placeholder you want emitted literally.

## Schema follows the board

The board is the source of truth. The skill discovers the schema (property names, types, enum options, templates, statuses) once at the start of every session and adapts to whatever exists.

- **Rename a property** (e.g. `Related Person` → `Persons`) → the next capture writes to `Persons`. No alias entry, no config edit.
- **Delete a property** (e.g. drop `Source URL`) → the next capture skips it silently and falls back to title-similarity for dedupe.
- **Add a new option to a multi-select** → the next capture can pick it via the LLM's matching pass.
- **Translate the board to another language** → the LLM matches semantically (`Étiquettes` → `Tags`, `Scadenza` → `Due date`).
- **Add a brand-new property** → it's discovered live, though the skill only writes to it if it recognizes the concept; otherwise it's left alone.

If the skill can't confidently map an inferred value to one of the board's live enum options, it asks you via a picker (`AskUserQuestion`) rather than silently miscategorizing. Picker options include up to three of the board's closest live options, a `Skip — leave empty` escape, and an `Other` free-text field that gets passed through to the backend (which may auto-create a new option on its end, depending on the backend's settings).

Only one property is strictly required: a title-typed property (any name). A status-typed property is recommended — when it's absent, the skill simply omits `Status` from the payload. Everything else is optional — if the board doesn't have it, the skill doesn't write it.

## First use

1. Install the plugin (`/plugin install quick-capture@<your-marketplace>`).
2. Make sure your personal board has at least a title-typed property. A status-typed property is recommended (the skill omits `Status` from the payload if the board doesn't have one). Any other properties you want the skill to fill (status, priority, tags, effort, due date, source link, related person) are optional — add them as you like, with whatever names and option labels suit you. The skill discovers and adapts to whatever's there.
3. Trigger the skill once — say `/personal-todo test capture` or paste a URL with "add to my todos". The skill runs **First-run setup**: four `AskUserQuestion` calls — three setup questions (which backend, your board URL, preferred date format) plus a write confirmation — with one access check in between, then it writes the three-field local config.
4. From then on, capture is silent — every subsequent invocation reads the local config, fetches the live board schema once per session, and writes directly to your board.

To reconfigure: say "reconfigure my board" or "switch board". The skill confirms and overwrites the existing config.

If an older config shape is found on disk (with extra keys like `tags`, `templates`, `property_aliases`, or a `backends.<name>` sub-block), the skill migrates it to the three-field shape on the first capture and surfaces a one-line notice. The extra keys are discarded because the workflow now rediscovers all schema-shaped state live.

## Backend

The skill talks to the board via a single swappable adapter file under [`skills/capture-todo/references/backends/`](skills/capture-todo/references/backends/). The active adapter is named at the top of [`SKILL.md`](skills/capture-todo/SKILL.md). Swapping backends is one pointer change plus a new adapter file — no core rewrite. See the [backends README](skills/capture-todo/references/backends/README.md) for the adapter contract.
