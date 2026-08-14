---
name: capture-todo
description: Capture a todo onto the user's personal task board (Notion or other supported backend) with structured properties and a concise body of deep links. Trigger on "add to my todos", "capture this", "track this", "log this", "follow up on…", "remind me to…", "park this", "note for later", on GitHub / GitLab / Notion / Teams / Linear URL pastes accompanied by capture intent, and on meeting follow-ups, paper-note transcriptions, or deferred ideas the user wants on the board. Creates a new entry or updates / extends an existing one.
---

# Capture todo

Capture an input — URL, paragraph, paper-note transcription, free-form thought — onto the user's personal task board as a single entry with structured properties and a compact, glance-able body of deep links.

The skill is **backend-agnostic**. Workflow, logical property model, and body rendering are vendor-free below. All board-specific details (vendor, MCP tool names, search syntax) live in the active backend adapter named immediately below.

## Principle: backend is the source of truth

The board's live schema (property names, types, enum options, templates, statuses, people) is the only source of truth. The skill discovers it at the start of every session and adapts to whatever exists. There is **no translation layer** persisted locally. If the user renames `Tags` to `Themes` on the board, the next capture writes to `Themes`. If they delete `Source URL`, the next capture skips it silently. Local state holds only the pointer (which backend, which board) and the user's locale preference — never a mirror of the schema.

When the skill cannot confidently map an inferred value to one of the board's live enum options, it asks the user via `AskUserQuestion`. It never invents an option, never silently miscategorizes, never persists a "best-guess" default to chase later.

## Active backend

**Adapter:** [`references/backends/notion.md`](references/backends/notion.md)

The adapter exposes these operations:

- `fetch_schema() → { properties, templates, status_default }`
- `search_by_source_url(url) → entry | null`
- `search_by_title_similarity(title) → [entry, …]`
- `resolve_person(name) → person_ref | null` (optional; may return `null` always)
- `create_entry(properties, body) → entry_url`
- `update_entry(entry_id, properties, body) → entry_url`
- `append_to_body(entry_id, body_fragment) → entry_url`

The `properties` argument on writes is a map keyed by **live property names** as returned from `fetch_schema()` — there is no logical-to-actual translation happening inside the adapter or in local config.

Never call the backend's underlying APIs or MCP tools directly for board reads or writes. Read the adapter file once at the start of an invocation, then route every board operation through the operations above. To swap backends: write a new adapter file under `references/backends/`, then flip the `Adapter:` line above to point at it.

## Local config

User-specific board location lives in **`~/.config/quick-capture/config.json`** — outside this repo, never committed. The skill reads it at the start of every invocation. The repo holds zero board identifiers, zero URLs, zero workspace names.

Skeleton:

```json
{
  "active_backend": "notion",
  "board_ref": "<full URL of the user's board>",
  "locale": { "date_format": "YYYY-MM-DD" }
}
```

Three fields. That is the entire local state.

- `active_backend` — name of the active adapter (must match a file under `references/backends/`).
- `board_ref` — opaque string the adapter parses to find the board. For Notion: a Notion database URL. The adapter derives any internal IDs (database ID, data source ID) at runtime from this URL; nothing is cached on disk.
- `locale.date_format` — one of `YYYY-MM-DD` (default, ISO), `DD.MM.YYYY`, `MM/DD/YYYY`. Used both for rendering user-facing dates in the body **and** for disambiguating ambiguous date input (e.g. `07/01/2026` parses as MM/DD when `MM/DD/YYYY`, as DD/MM when `DD.MM.YYYY`, rejected as ambiguous when `YYYY-MM-DD`).

Storage notes:

- XDG standard. When `XDG_CONFIG_HOME` is set, prefer `$XDG_CONFIG_HOME/quick-capture/config.json`.
- On Unix-like systems: restrict to single-user with `chmod 600`.
- On Windows: rely on default user-profile ACLs; do not attempt `chmod`.
- Single-user use. Hand-editing is supported — the skill re-reads on every invocation.

If the file is missing, run the active adapter's **First-run setup** before the main workflow. If the file contains any key outside the three fields above (a legacy config from before this redesign), run the **Migrate to current shape** step below before the main workflow.

## When to use

Activate when the user signals intent to put something onto their personal task board. Strong signals:

- Explicit imperative — "add to my todos", "capture this", "track this", "log this", "park this", "note for later", "remind me to…", "follow up on…".
- The `/personal-todo` slash command — always invokes this skill regardless of phrasing.
- A URL paste from a known source system (GitHub, GitLab, Notion, MS Teams, Linear, etc.) accompanied by intent phrasing.
- A paper-note transcription ("from my notebook", "I wrote down") followed by an actionable phrase.
- A meeting-derived action ("from today's 1:1", "follow-up from the design review", "I owe X to Y").

## When NOT to use

- The user asks to *do* the task immediately rather than capture it for later.
- The user is browsing or discussing the source system — no capture intent stated.
- The user asks to capture into a different system (e.g. a team-shared tracker). This skill targets the personal board only.
- The conversation is a code-review or implementation thread with no separate follow-up surfaced.

## Workflow

### 0. Load config

Read `~/.config/quick-capture/config.json`.

- **File missing** → run the active adapter's **First-run setup**. Every user input goes through `AskUserQuestion` (one question per call, free-text via the "Other" fallback). The user must explicitly confirm before the config file is written. After setup, continue with step 0.5 and the original capture request.
- **File present, exactly the three fields above** → carry on.
- **File present, contains any legacy key** (`version`, `tags`, `templates`, `property_aliases`, any nested `backends.*` block) → run **Migrate to current shape** (below), then carry on.
- **File present, missing one of the three fields** → run the relevant slice of first-run setup to fill the gap (typically asking only the missing question).
- **Later step fails with a board-access error** (404, 401, "data source not found") → assume the `board_ref` is stale and offer to re-run first-run setup via `AskUserQuestion`. On successful re-setup, retry the failing capture from step 0.5 (do **not** force the user to re-issue the original prompt).

#### Migrate to current shape

Triggered once when the on-disk config carries any legacy key. Build the three-field object — `active_backend` and `locale` preserved from the old file; `board_ref` preserved from whatever URL field the legacy adapter used (`backends.<active_backend>.board_url` for Notion). Overwrite the file. Surface one line: `Config migrated to current shape (board_ref + locale only). The board is now the source of truth for property names, tags, templates, and statuses.` All other legacy keys are discarded silently — they held derived schema state that is now rediscovered live. If a needed value is unrecoverable (e.g. no URL field at all), ask the user via `AskUserQuestion` before writing. Idempotent: a config already in the current shape triggers no rewrite and no notice.

### 0.5. Discover the board schema (session-cached)

Call the adapter's `fetch_schema()` once per session. Cache the returned object for the remainder of the conversation; all subsequent steps in this and later captures within the same session read from the cache. A new session refetches.

The returned schema has the shape:

```
{
  properties: [{ name, type, options? }, …],
  templates:  [{ id, name, body_markdown, property_defaults }, …],
  status_default: "<first option of the Status-typed property, or null>",
}
```

Each property is reported with its **live name** (the name as it currently appears on the board). Enum-typed properties (single-select, multi-select, status) include their live `options` list. Templates carry their `property_defaults` keyed by live property names.

On fetch failure (auth, network, board deleted), the adapter returns an empty schema with an error indicator (`{ properties: [], templates: [], status_default: null, error: "<message>" }`). The skill surfaces the error in one line and offers to re-run first-run setup via `AskUserQuestion`. Do not fall back to a hardcoded schema — there is none.

**Cache invalidation.** The cache is per-session and otherwise immutable. If a subsequent operation fails with a property-not-found symptom (signaling the cached schema is out of step with the board — e.g., the user added/removed a column between captures), refetch the schema once and retry the operation. If the second attempt fails the same way, surface the error verbatim and stop. Do not refetch on every error — only on errors that look like schema drift.

**Shared lifetime with session memos.** The schema cache and the `property_memo` / `enum_memo` / `template_memo` (see Session memos (step 5.3) below) share a single lifetime: they are all created when step 0.5 first fires, and they are all cleared together when the cache invalidates or the session ends. A refetch never preserves stale memos against a fresh schema.

### 1. Parse the input

**Extract template override tokens.** Before identifying the source kind, scan the raw input for template override tokens. Detection runs on every branch (create / update / extend) so flag tokens never leak into the body; the resulting decision is consumed only by step 5.5 (skipped on `update` / `extend`).

Flag form (case-insensitive, whitespace-anchored — each token must be preceded by start-of-text or whitespace, and the bare / unquoted form must be followed by whitespace or end-of-text):

- `template:"<multi word name>"` — quoted form; greedy on quote-balance, an unclosed quote falls back to the unquoted form at the next whitespace.
- `template:<name>` — `<name>` continues until the next whitespace.
- `no-template` — bare token.

URLs like `https://wiki/template:foo` therefore do not match (preceded by `/`, not whitespace). Tokens inside fenced code blocks (`` ``` `` … `` ``` ``), inline code spans (`` `…` ``), and markdown link targets `[label](…)` are skipped. When multiple flag tokens appear, last-occurrence wins. All detected flag tokens are removed from the input; surrounding whitespace collapses to a single space.

Retain two values for downstream steps: the **stripped text** (used by every step from this point on) and the **override decision** (one of `null` / template-name / `"__none__"`, consumed in step 5.5 substep 2). Natural-phrase fallback runs in step 5.5 against the **original raw text**, not the stripped text, since the LLM intent check needs the surrounding context.

**Identify the primary source kind** by URL host, mention pattern, or free-form signal:

| Signal | Source kind |
|---|---|
| `github.com/.../issues/N`, `.../pull/N` | `GitHub` |
| `gitlab.com/...` or any `*.gitlab.com/...` | `GitLab` | <!-- pii-ok: pattern-doc -->
| `notion.so/...`, `*.notion.site/...`, `app.notion.com/...` | `Notion` | <!-- pii-ok: pattern-doc -->
| `teams.microsoft.com/...`, "Teams thread", "in Teams chat" | `Teams` | <!-- pii-ok: pattern-doc -->
| `linear.app/...` | `Linear` | <!-- pii-ok: pattern-doc -->
| Paper / notebook phrasing | `Paper` |
| Free-form thought without external anchor | `Idea` |
| Meeting follow-up phrasing | `Conversation` |
| Anything else | `Other` |

**Normalize any source URL** before further use: lowercase the host, strip trailing slashes, strip query params that are obviously tracking (`utm_*`, `ref`, `fbclid`, `gclid`, etc.), strip fragments. Keep query params that identify the resource (`?v=…` on Notion view URLs, `?id=…` where the host needs it).

### 2. Fetch primary source metadata (1 call max)

Source kind → connector mapping. Source-side connectors are **independent of the active board adapter** — they reach the source's vendor (GitHub, Notion-as-source, GitLab, etc.) not the board. The board-side adapter is not used in this step.

| Source kind | Connector |
|---|---|
| `GitHub` | `gh issue view <url>` / `gh pr view <url>` via `Bash` |
| `GitLab` | GitLab MCP `get_issue` / `get_merge_request` / `search` |
| `Notion` (as source) | Notion MCP `notion-fetch` against the source URL |
| `Teams` | MS 365 MCP `chat_message_search` with a relevant query |
| `Linear` | Notion AI search via the Notion connector |
| `Paper` / `Idea` / `Conversation` / `Other` | skip — no fetch |

If the fetch fails (network, auth, permissions), continue with what you have. Don't block capture on a missing snapshot.

### 3. 1-hop enrichment (optional, 1 extra call max)

Look for one obvious related artifact:

- GitHub issue → linked PR (and vice versa)
- GitLab issue → linked MR
- Notion source page → first mentioned ticket or external link in its body
- Linear ticket → linked PR or design doc

Stop after one hop. If nothing surfaces in one call, move on.

### 4. Search the board for duplicates via the adapter

1. Call `search_by_source_url(normalized_url)`. The adapter looks up the live URL-typed property whose name best matches "Source URL" by applying the [matching tier sequence](references/matching.md) (filtered to `url`-typed candidates) against the schema cached in step 0.5, then queries it. If no URL-typed property exists on the board, the adapter returns `null` without an error — dedupe by URL simply isn't available on this board, and the workflow falls through to title similarity.

   On a match, display a 1-line summary of the existing entry (`Name`, `Status`, `Created time`) and ask via `AskUserQuestion`:
   - `update` — overwrite properties + replace body. **Caveat:** multi-select properties like `Tags` are overwritten with newly-inferred values; if the user added manual tags, prefer `extend` instead.
   - `extend` — append new context to the existing body, leave properties.
   - `create new` — new sibling entry (rare; for a genuinely different follow-up off the same source).
2. No URL match → call `search_by_title_similarity(generated_title)`. Title comparison is **normalized** before scoring: lowercased, punctuation stripped, runs of whitespace collapsed. If a close match surfaces (token-overlap ratio ≥ 0.6 against the normalized title — the skill's threshold, not the adapter's), show it and ask `update existing` / `create new` (default: `create new`).
3. No match at all → proceed to create.

For `Paper` / `Idea` (no URL), skip step 1 and go directly to title-similarity.

### 5. Infer values and map to the live schema

Two sub-steps: infer the values from input (vendor-free), then map each value onto whatever property currently exists on the board.

#### 5.1. Infer logical values

For each logical field defined in [`references/property-model.md`](references/property-model.md), infer the value from the input per that file's rules. Two cases need explicit handling here because they depend on session state rather than input signals alone:

- `Status` — on create: use the schema's `status_default` from step 0.5 unless a selected template in step 5.5 explicitly sets a different value. If `status_default` is `null` (the board has no status-typed property), omit `Status` from the payload. On update: leave the existing value untouched (the user owns Status transitions).
- `Source URL` — when no URL is available (`Paper`, `Idea`), omit. The body still records the source kind via the source-of-source line in the body template.

Inference also produces three **body-state fields** that feed both the no-template body render (step 6) and the template-path placeholder substitution (step 6.1):

- `context` — one-sentence (≤120 chars) summary of what the user wants captured, written as a verb-first imperative. Derived from the input's primary action verb and the named artifact. **Always set.** Inline-links any named artifact mentioned in the sentence per the rules in [`references/body-template.md`](references/body-template.md).
- `why` — one short prose line (1–2 sentences) capturing the motivation behind the capture: what triggered it, what is at stake, whose decision drives it. Derived from input signals like "because…", "blocks X", "owner asked for…", or from fetched source metadata. **Empty if no motivation signal is present** — never invented.
- `next` — 1–3 short bullet strings each starting with a verb, capturing the next action(s) the user implied. Derived from input phrasing like "ping `<name>`", "draft proposal", "review by Friday". **Empty if no action signal is present** — never invented.

These three are not board properties; they are skill-internal prose computed once and reused. Empty `why` / `next` is normal. The body template (no-template path) omits empty blocks; step 6.1 (template path) leaves their placeholders literal as hand-fill cues per [`references/placeholders.md`](references/placeholders.md). Both paths consume the same values, so the rendered prose is consistent regardless of which path runs.

Inference produces a map of **logical field name → inferred value(s)** plus the three body-state fields. The next sub-step translates the property map onto live property names; the body-state fields feed step 6 / 6.1 directly without going through any schema mapping.

#### 5.2. Map onto live schema

Two passes. Pass 1 walks every (logical field, inferred value) and resolves it against the live schema; any field that lands at tier 6 is appended to an `enum_miss_queue` instead of being prompted immediately. Pass 2 fires a single batched `AskUserQuestion` containing the queue (capped at 4 questions per tool call). The user answers all at once; the skill applies the answers, then proceeds to step 5.5.

##### Pass 1: resolve each field through the tier sequence

For each (logical field, inferred value) pair from 5.1:

1. **Memo lookup.** If the logical field has an entry in `property_memo` (see Session memos (step 5.3) below), reuse the memoized live property name. Skip to step 4. Otherwise continue.
2. **Find the live property.** Apply the [matching tier sequence](references/matching.md) to the logical field name against the cached schema's `properties` list. The first tier hit gives the live property name. A tier-6 fall-through on a property name means no semantically matching property exists on the board — **skip the field silently** (do not queue this case for prompting; missing properties are a board-shape decision the user already made). On any hit, write the (logical → live) decision to `property_memo` for the rest of the session.
3. **Reject read-only types.** If the matched live property has type `formula`, `created_time`, `updated_time`, `relation`, or `unknown`, skip the field with a one-time per-session notice (`Property "<name>" is read-only or unsupported; skipped.`). These types either reject writes or have ambiguous write semantics across backends.
4. **Pick the live value.** If the matched property is enum-typed (single-select / multi-select / status), the inferred value must be expressed as one of the property's live `options`:
   - **Memo lookup.** If `enum_memo` has an entry keyed by `(live property name, inferred-intent string)` matching this case, reuse the memoized live option. Skip to step 5.
   - **Apply tiers 1–5** from [`references/matching.md`](references/matching.md) to the inferred value against the live `options` list. A hit yields the live option name.
   - **Tier-6 fall-through** → append `{ property, inferred_value, options }` to the `enum_miss_queue`. Do **not** fire `AskUserQuestion` here — pass 2 collects them.
5. **Build the payload.** Insert `{ <live property name>: <live value> }` into the in-progress write payload (or leave the slot pending if it's queued for prompting).

##### Pass 2: batched enum-miss prompt

If `enum_miss_queue` is empty after pass 1, skip pass 2 entirely.

Otherwise fire **one** `AskUserQuestion` call with one question per queued field, capped at the tool's 4-question limit:

- `header`: the live property name (e.g., `Tags`).
- `question`: `<live property name> — pick the closest match for "<inferred intent>":` where `<inferred intent>` is the value the skill would have written (or the user's original phrasing if more illustrative).
- `options`: up to 3 live options on the board, sorted by tier-5 closeness score (descending), plus `Skip — leave empty`.
- `multiSelect`: `true` when the property is multi-select (e.g., `Tags`); `false` otherwise.

If the queue holds more than 4 items, prompt for the first 4 and append a one-line `Couldn't fit "<field>" in this prompt; left empty. Re-run capture to set it.` for each overflow field. (Cap is the tool's hard limit; in practice no realistic capture produces five enum-misses.)

`AskUserQuestion`'s built-in `Other` free-text fallback handles "none of these fit". When the user types `Other`:

- **Multi-select properties** → the typed value goes into the write payload as a one-time tag for this entry. Backends like Notion auto-create the option on their end; the skill does **not** confirm with the user, does not loop, does not persist anything new client-side. Risk of typo bloat is the same as typing directly in the Notion UI.
- **Single-select properties** → same behavior. The backend may reject the unknown value (in which case the adapter surfaces a one-line skip notice and continues); Notion's `Select` type auto-creates options like multi-select does.

When `Skip — leave empty` wins, the field is omitted from the payload.

After the user answers, every non-`Skip` answer is memoized into `enum_memo` keyed by `(live property name, inferred-intent string)`. The pair becomes the next session-memo lookup hit for the same intent string.

Never silently fall back to a default like `Medium` or `Engineering` when the enum match is ambiguous. Ask.

#### 5.3. Session memos

Three in-conversation memos accelerate captures within the same session. All are populated automatically during the relevant workflow step; none is persisted to disk.

- **`property_memo`** — map of logical field → live property name. Populated on every successful tier-1-through-tier-6 hit at 5.2's pass 1 step 2. On subsequent captures, the memo is consulted first; a hit bypasses the tier sequence entirely.
- **`enum_memo`** — map of `(live property name, inferred-intent string)` → live option name. Populated on every non-`Skip` answer at the batched prompt in 5.2's pass 2. On subsequent captures, an exact intent-string match yields the same answer without re-prompting. **No fuzzy memo lookup** — `platform stuff` and `platform work` are different keys.
- **`template_memo`** — the user's last template choice in this session. Three states: `null` (unset, default), a live template name string (specific template chosen), or the sentinel `"__none__"` ("No template" chosen). Written at every fresh resolution in step 5.5 — prompt pick or in-prompt override. On subsequent captures, step 5.5 reuses the memoized choice and skips the prompt; override per-capture via `template:<name>` / `no-template` flag tokens or a natural-phrase signal in the prompt.

All three memos share a lifetime with the schema cache from step 0.5: created together, refreshed together on cache-invalidation refetch (so a renamed / deleted property or template doesn't keep a stale memo entry), and cleared together at session end.

Two sub-commands let the user inspect or reset memos mid-session:

- **`/personal-todo memos`** — print the current `property_memo`, `enum_memo`, and `template_memo` contents as a plain-text summary. Read-only.
- **`/personal-todo forget`** — clear all session memos without invalidating the schema cache. Use when the user wants to re-evaluate a decision that's been memoized this session (e.g., they realize they picked the wrong option earlier and want the next capture to re-prompt).

Neither command writes to disk.

### 5.5. Discover and select a board template (create path only)

Skipped on `update` and `extend` — templates apply only to fresh entries. On `update`, body content is re-rendered via [`references/body-template.md`](references/body-template.md) regardless of whether the entry was originally created from a template. On `extend`, only the appended fragment is rendered (also via the body template); the existing body is left untouched.

The choice resolves through one of three paths (priority order): override in the prompt → `template_memo` reuse → `AskUserQuestion` prompt. Whichever path produces a fresh choice writes back into `template_memo` so the next capture inherits it.

1. Read the cached schema's `templates` list (from step 0.5). No extra adapter call. Empty list → no-template branch immediately, skip the rest of this step (no override / memo / prompt logic applies when there's nothing to choose from).

2. **Override resolution.** The flag-form decision was already extracted in step 1; flag wins over natural-phrase when both fire.
   - **Flag form** — use the decision from step 1 (`null` / template-name / `"__none__"`). Match the canonical template name case-insensitive, trimmed, against the cached template list.
   - **Natural-phrase form** — only runs when the step-1 decision is `null`. Bounded LLM intent check against the original raw input (pre-strip), supplied with the live template names; asks "did the user signal which template (or no template) to use?" Accept only at confidence ≥ 0.8 (same threshold as tier 4 in [`references/placeholders.md`](references/placeholders.md)); below threshold → no override.

   Override target resolution:
   - Known template name → continue to substep 5 (validate) and substep 6 (merge). Write the canonical live name into `template_memo`.
   - No-template → skip 5 / 6 and go to step 6. Write `"__none__"` into `template_memo`.
   - Flag-form name not in the cached template list → surface `No template named "<X>" found; falling back to skill body.` and proceed as no-template. **Do not** write the unknown name into `template_memo`; leave the prior memo state untouched.

   When neither flag nor natural-phrase yields an override, fall through to substep 3.

3. **Memo lookup** (runs when no override fired).
   - `template_memo` unset → fall through to the prompt (substep 4).
   - `template_memo` holds a template name → validate the name still exists in the cached template list. Miss (renamed / deleted) → drop the entry silently, fall through to the prompt. Hit → surface `Using your "<name>" template (remembered).` and continue to substeps 5 / 6.
   - `template_memo` holds `"__none__"` → surface `No template (remembered).` and go to step 6.

4. **Prompt** — when neither override nor memo resolved the choice. Ask via `AskUserQuestion` (`header`: `Template`, `question`: `Which template should this todo use?`). Options: up to 3 templates (label = template name; description = first ≤80 chars of `body_markdown` after stripping leading whitespace and `#`-style heading markers — so the description carries actual content, not formatting), plus a final option `No template — render the skill body`. **Cap:** `AskUserQuestion` allows at most 4 options total; the schema lists templates sorted by recency / lexical order — surface only the top 3. The user can pick a 4th-or-later template by typing its exact name into the `Other` free-text fallback — matched case-insensitive, trimmed, against the full list. Never auto-apply a template, even when only one exists. Branch on the choice:
   - Specific template → substeps 5 / 6. Write the canonical name into `template_memo`.
   - `No template` → no-template branch (skip 5 / 6, go to step 6). Write `"__none__"` into `template_memo`.
   - Unrecognized `Other` name → surface `No template named "<X>" found; falling back to skill body.` and proceed as no-template. **Do not** write the unknown name; leave the memo unset.

5. **Validate the selected template's body.** If `body_markdown` is empty or whitespace-only after trimming, surface `Template "<name>" has no usable body; falling back to skill body.` and proceed as no-template. Write `"__none__"` into `template_memo` so the fallback sticks for follow-up captures.

6. **Merge property defaults** into the payload built in 5.2. Templates contribute `property_defaults` keyed by live property names. Precedence rules apply per-field:

   | Field semantics | Rule |
   |---|---|
   | `Status` (or the schema's Status property by any name) | Template-explicit Status wins over the schema's `status_default`. If the template sets a value, surface a one-line `Template sets Status to <X>` notice so the user can correct if unintended. |
   | Date-typed (e.g. `Due date`) | skill-explicit > template-explicit > absent. |
   | Single-select with a skill default (e.g. `Effort`, `Priority`) | skill-explicit > template-explicit > skill-default. |
   | Single-select without a skill default | skill-explicit > template-explicit > absent. |
   | Person reference (e.g. `Related Person`) | skill-explicit > template-explicit > absent. |
   | Multi-select (e.g. `Tags`) | **union** of skill-inferred and template-explicit option sets, deduplicated. |

   "skill-explicit" = inferred from an actual input signal (e.g. user said "urgent" → `Priority: High`). "skill-default" = fallback because no signal was present (e.g. `Effort: Medium`).

   For multi-select properties specifically: when the template carries an option the live schema does not yet have, pass it through as a free-form value. The backend may auto-create the option (Notion does) or reject it (in which case the adapter surfaces a one-line skip and continues).

   The merged payload is held in memory for this invocation only; `template_memo` (the chosen name or `"__none__"`) is the only across-capture cache, and merged defaults are recomputed on every capture.

Note: when no template is in play (empty list, user picked `No template`, validation fell back, or memo / override resolved to `"__none__"`), step 5.1's `Status: status_default` and the skill-inferred `Priority` / `Effort` / `Tags` defaults all apply unchanged. No `Template sets Status to <X>` notice fires.

### 6. Render the body

- **A template was selected in step 5.5** → start with the template's `body_markdown`. Run step 6.1 below to substitute placeholders, then append `<!-- AI-drafted, {date} -->` on its own line. The template is canonical: the skill does not inject context lines, source snapshots, or links into the template body beyond placeholder substitution. The source URL still lives in the URL-typed property (when that property exists on the board), so the link is never lost.
- **No template selected** → follow [`references/body-template.md`](references/body-template.md). Skip sections that aren't derivable. Mark snapshot content with the capture date. Step 6.1 is **skipped** entirely on this path — placeholders apply only to template bodies.

#### 6.1. Substitute placeholders in the template body

Runs only on the template-selected branch.

Templates may carry any `{…}` brace content — strict identifiers (`{name}`), prose hints (`{ToDo one-liner}`, `{Why summary and/or purpose}`), or arbitrary tokens. The skill applies the [resolution tier ladder](references/placeholders.md#resolution-tiers) (exact → normalized → translation table → LLM-fuzzy ≥ 0.8 → leave literal) to map each detected brace onto a recognized identifier, then substitutes from in-memory state.

State available for substitution:

- The write payload built in step 5.2 + 5.5 (keyed by live property names).
- The three body-state fields from step 5.1 (`context`, `why`, `next`).
- Inferred capture-time values not bound to a board property: today's `date`, the fetched `source_title` / `source_status` from step 2, the 1-hop `related_url` / `related_label` from step 3, the source kind.

No lookup goes through an alias map — the placeholder vocabulary is the skill's stable logical field set documented in [`references/placeholders.md`](references/placeholders.md).

Algorithm summary (full version in `placeholders.md`):

1. Replace every `{{…}}` escape with a sentinel.
2. For each remaining `{…}`, walk the tier ladder. Record `(brace, identifier, qualifiers)` on a hit; mark unrecognized on a fall-through.
3. For each recorded triple, substitute per the rules in `placeholders.md`: present value → substitute (apply length caps from captured qualifiers); empty value with a conditional qualifier (`if available` / `(optional)` / etc.) → substitute empty silently; empty value without a conditional qualifier → leave the brace literal as a hand-fill cue.
4. Restore sentinels to literal `{…}`.
5. Append the AI-drafted marker as the final line.

Notice surfacing:

- ≥1 placeholder substituted → `Filled <N> placeholder(s).`
- ≥1 recognized-but-empty placeholder left literal → `Left <N> placeholder(s) literal for hand-fill: {foo}, {bar}.` (cap example list at 5).
- ≥1 unrecognized placeholder left literal (tier 5 fall-through) → `Left <N> unrecognized placeholder(s) literal: {baz}.` (cap at 5).
- All three independent; all suppressed when the template has no `{…}` at all.

### 7. Write to the board

Call `create_entry` (no match), `update_entry` (overwrite chosen), or `append_to_body` (extend chosen). The `properties` payload uses live property names from step 5.2.

Error handling:

- Adapter raises a board-access error (auth, 404, schema-related write failure) → tell the user what failed in one line. If the error pattern matches stale config (404 on the board, 401, "database not found"), offer to re-run first-run setup via `AskUserQuestion`.
- Adapter raises a transient error (network, rate limit, 5xx) → retry once with a 1-second backoff, then surface the error verbatim.
- Adapter succeeds → return the entry URL as the last user-facing line. **Do not name the backend vendor.**

## Anti-patterns

**Persistence + drift**

- **Don't persist any schema-shaped data.** Property names, enum options, template names, status defaults are discovered live each session. The only persistent state is `active_backend` + `board_ref` + `locale`.
- **Don't persist session memos to disk.** `property_memo`, `enum_memo`, and `template_memo` live in conversation state only. Writing them to disk resurrects the translation-layer pattern: a frozen snapshot of one moment's decisions that the live board then drifts away from.
- **Don't fuzzy-match memo keys.** `enum_memo` reuses an answer only on exact intent-string equality. Loosening to fuzzy match would let "platform work" answers leak into "platform stuff" captures.
- **Don't reintroduce a translation layer.** When a future feature seems to need a logical-to-actual property-name map, the right fix is smarter live matching in step 5.2 (extending [`references/matching.md`](references/matching.md)'s translation table is allowed; persisting per-user aliases is not).
- **Don't validate schema at first-run setup.** Setup records only the pointer; the board's schema is queried at capture time. A board with only `Name` + `Status` works; a board with 20 custom properties works.

**Defaults + ambiguity**

- **Don't auto-extend the board client-side.** When an enum match is ambiguous, ask via `AskUserQuestion`. The backend may auto-create on write (Notion does) — that's the user's explicit choice via `Other`, not a skill-side default.
- **Don't silently fall back to a default when uncertain.** Defaults (`Priority: Medium`, etc.) apply only when **no signal was present**. Signal-present-but-ambiguous → ask.
- **Don't fill date-typed fields from urgency words.** A `Due date` needs an explicit date. Urgency goes to `Priority`.

**Body content**

- **Don't write large or wholesale-copied bodies.** Body ≤ ~15 lines. Snapshot fields are title + status + 1–2 key facts, not full source descriptions. External content goes stale; deep links don't.
- **Don't fish across MCPs for related context.** Enrichment is bounded to primary source + 1 hop.
- **Don't silently update an existing entry.** Show the 1-line summary first; the default action is the one that least surprises. `update` overwrites multi-select properties with inferred values and loses manual edits — prefer `extend` when unsure.
- **Don't overwrite `Status` on update.** Property updates touch metadata only; the user owns `Status` transitions.

**Templates**

- **Don't inject the skill-rendered body into a template body.** When a template is selected in step 5.5, the template body is canonical — only the AI-drafted marker is appended (after placeholder substitution per step 6.1).
- **Don't drop template property defaults silently.** Apply per the merge table in step 5.5.
- **Don't let template defaults override explicit user intent.** Input "urgent" wins over any template-set `Priority`.

**Architecture + privacy**

- **Don't bypass the active adapter for board reads/writes.** Extend the adapter contract in [`references/backends/README.md`](references/backends/README.md) first; never call backend MCP tools directly from workflow paths.
- **Don't hardcode any user-specific value in skill files.** Board URLs, IDs, workspace names, locale preferences live in `~/.config/quick-capture/config.json`.
- **Don't name the backend vendor in user-facing output.** Say "captured to your board" with the returned URL.
- **Don't log or echo the input payload outside the board write.** The only sink for potentially-private input is the user's own board.
- **Don't write anything back to the source surface.** No comments, no backlinks, no mentions. The source may be shared with people unrelated to the user's personal tracking.
