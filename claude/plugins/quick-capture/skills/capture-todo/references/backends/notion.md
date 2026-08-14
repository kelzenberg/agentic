<!-- AI-drafted, 2026-06-09 -->

# Notion adapter

Adapter that lets the `capture-todo` skill talk to a Notion database as the personal task board. This file describes the **protocol** for talking to Notion. User-specific board location lives in local config as `board_ref` — never in this repo.

This adapter is the only file in this plugin that names Notion-specific MCP tool names.

## 1. Identity

| Field | Source |
|---|---|
| Vendor | Notion |
| Active adapter name | `notion` |
| Accepted `board_ref` shape | A full Notion database URL — see section 2 for accepted forms. |
| Runtime identifiers | Database ID and data source ID are derived from `board_ref` at session start; never persisted. |

## 2. Local config

The skill's three-field local config is documented in [`../../SKILL.md`](../../SKILL.md). For this adapter:

- `active_backend` = `"notion"`.
- `board_ref` = a Notion database URL. Accepted shapes:
  - `https://www.notion.so/<workspace>/<page-title>-<32-hex-id>` <!-- pii-ok: pattern-doc -->
  - `https://www.notion.so/<workspace>/<32-hex-id>?v=<view-id>` <!-- pii-ok: pattern-doc -->
  - `https://app.notion.com/p/<workspace>/<32-hex-id>?v=<view-id>`
  - `https://<workspace>.notion.site/<32-hex-id>` <!-- pii-ok: pattern-doc -->
- `locale.date_format` — standard.

**Runtime ID derivation.** On every session (during `fetch_schema()` or any first operation), the adapter:

1. Parses `board_ref` to extract the **database ID**: take the last 32-hex-character segment in the path and insert hyphens at positions 8-4-4-4-12 (e.g. `a1b2c3d4e5f6...` → `a1b2c3d4-e5f6-...`). If the URL already contains a hyphenated UUID, use it as-is.
2. Calls `mcp__claude_ai_Notion__notion-fetch` with the database ID to obtain the **data source ID** from the returned `<data-source url="collection://...">` tag. The data source ID is the value the Notion-search `data_source_url` parameter needs (`collection://<data_source_id>`).
3. Holds both IDs in-process for the duration of this session. The next session re-derives. Neither value is written to disk.

If parsing fails, surface the error in one line and offer to re-run first-run setup via `AskUserQuestion`.

## 3. First-run setup

Runs automatically when `~/.config/quick-capture/config.json` is missing. Four `AskUserQuestion` calls (three setup questions plus a write confirmation); the board's schema is **not** validated here.

Every user input goes through the `AskUserQuestion` tool — not bare text prompts. One question per tool call. The free-text fallback (the implicit "Other" option) is used for inputs that don't fit predefined choices (URLs).

1. **Pick backend.** `header`: `Backend`, `question`: `Which board backend should quick-capture use?`. Today the only shipped adapter is `notion`, so present a single option `Notion` (recommended) plus the implicit "Other" fallback for future adapters. Skip when the user already has a working config and is only filling in a missing field.

2. **Get board reference.** `header`: `Board URL`, `question`: `Paste the full Notion URL of the database you want to use as your board.`. Present one option `Paste my URL` with a description listing the accepted URL shapes (see section 2); the user pastes their URL into the "Other" free-text field.

3. **Pick locale.** `header`: `Date format`, `question`: `Which date format do you use?`. Options: `YYYY-MM-DD (ISO)`, `DD.MM.YYYY (European)`, `MM/DD/YYYY (US)`. Used for body-side date rendering and slash-style input disambiguation.

4. **Verify access.** Derive the database ID per section 2, then call `mcp__claude_ai_Notion__notion-fetch` with that ID. Confirm the response is a database (top-level `<database>` block). On 401 / 403 / 404, re-prompt step 2 via `AskUserQuestion` explaining what failed and asking the user to either paste a different URL or confirm Notion connector access.

5. **Confirm before writing.** `header`: `Confirm`, `question`: `Write config to ~/.config/quick-capture/config.json now?`, options `Yes, write config (recommended)` and `No, cancel setup`. On `No`, leave any existing config file untouched and abort the capture.

6. **Write the file.** `mkdir -p ~/.config/quick-capture` (use `XDG_CONFIG_HOME` if set). Write the three-field config JSON. On Unix-like systems: `chmod 600`.

7. Confirm to the user (plain output, no question): `Config written. Captures will go to your board.` Do not name the vendor in the confirmation line, do not echo the URL.

8. Continue with the original capture request — the workflow's session-start `fetch_schema()` will discover whatever schema the board carries.

The user can re-run setup at any time with phrases like "reconfigure my board" or "switch board" — confirm via `AskUserQuestion` (`Yes, overwrite` / `No, keep current`) before overwriting.

## 4. Schema discovery

`fetch_schema() → { properties, templates, status_default }`

Single live read against the board, called once per session by the skill and cached for the rest of the conversation. Implementation:

1. Ensure runtime IDs are derived per section 2. (One-time per session; this is the cheapest place to do it.)
2. Call `mcp__claude_ai_Notion__notion-fetch` with `id`: `<database_id>`.
3. From the response, build the `properties` list. For each Notion property in the database's `<properties>` block:
   - `name` — the property's live label as it currently appears in Notion.
   - `type` — translated from the Notion type to the skill's normalized set:
     | Notion type | Normalized |
     |---|---|
     | `title` | `title` |
     | `rich_text` | `text` |
     | `select` | `select` |
     | `multi_select` | `multi_select` |
     | `status` | `status` |
     | `date` | `date` |
     | `url` | `url` |
     | `people` | `person` |
     | `created_time` | `created_time` |
     | `last_edited_time` | `updated_time` |
     | `formula`, `rollup` | `formula` |
     | `relation` | `relation` |
     | anything else | `unknown` |
   - `options` — for `select` / `multi_select` / `status` types, the live array of option names. Omitted for other types.
4. Build `status_default`: the first option of the `status`-typed property if one exists; `null` otherwise.
5. Build `templates` per the "Templates" sub-section below.
6. Return the assembled object.

On error at any step: return `{ properties: [], templates: [], status_default: null, error: "<one-line message>" }`. Never throw. The skill detects the empty schema and surfaces a re-setup prompt via `AskUserQuestion`.

### Templates

Notion stores page templates as special pages under the database, flagged as templates. The Notion MCP exposes them through the `notion-fetch` response on a database, but the response shape varies by MCP server version.

1. Inspect the database fetch response for template entries. Recognized shapes, in order of preference:
   - A `<templates>` block listing template page IDs and names.
   - A `<children>` block where some entries carry `is_template: true` (or equivalent flag).
   - Absent — the MCP version in use does not surface templates. Return `templates: []`.
2. For each template found, call `mcp__claude_ai_Notion__notion-fetch` on the template's page ID to retrieve:
   - `body_markdown` — the template's body content (enhanced markdown — the MCP returns this directly; use verbatim).
   - `property_defaults` — partial map of **live Notion property names → live values** for every property the template page carries an explicit non-empty value on. Omit empty / unset properties so the skill's merge logic doesn't treat them as `template-explicit`.
3. Sort the returned list: most-recently-modified first if the response carries `last_edited_time`, lexical by name otherwise. The skill surfaces only the top 3 in its template picker.

Recovery: if any per-template fetch fails (auth, malformed shape), include whatever templates were successfully retrieved and continue. A partial list is acceptable; an exception is not.

## 5. Operations

All operations go through the Notion MCP server. Tool names below are exact. Every reference to a `database_id`, `data_source_id`, or `data_source_url` resolves at runtime per section 2 — no values are hardcoded in this file.

Let `DSID` = the data source ID derived for the current session. The Notion-search `data_source_url` parameter is always `collection://<DSID>`.

The `properties` argument on writes is a map keyed by **live Notion property names** (as returned by `fetch_schema()` in section 4) → values. The adapter performs no logical-to-actual translation; it writes what the skill passes.

### `search_by_source_url(url) → entry | null`

1. From the cached schema, find the live `url`-typed property whose name best matches "Source URL" by applying the [skill's matching tier sequence](../matching.md) (filtered to `url`-typed candidates). If no `url`-typed property exists, return `null`.
2. Normalize `url`: lowercase host, strip trailing slash, strip tracking query params, strip fragment. Keep resource-identifying query params.
3. Call `mcp__claude_ai_Notion__notion-search` with:
   - `query`: the normalized URL string
   - `data_source_url`: `collection://<DSID>`
   - `page_size`: 5
   - `content_search_mode`: `workspace_search` (faster, no AI)
4. Iterate results in returned order. For each, fetch via `mcp__claude_ai_Notion__notion-fetch` and read the value of the URL property identified in step 1. **Short-circuit on the first page whose value equals the normalized input URL** — don't fetch remaining results. Worst-case cost: 2 calls (search + 1 fetch) on a hit; 1 + N on a miss (N ≤ 5).
5. Return the matching page if found. Else `null`.

Quirk: Notion search is full-text; the normalization step widens the match probability.

### `search_by_title_similarity(title) → [entry, …]`

1. Call `mcp__claude_ai_Notion__notion-search` with:
   - `query`: `title`
   - `data_source_url`: `collection://<DSID>`
   - `page_size`: 5
   - `content_search_mode`: `workspace_search`
2. Return up to 3 results, scored by token overlap against `title`. Threshold and ordering decided skill-side.

### `resolve_person(name) → person_ref | null`

1. Call `mcp__claude_ai_Notion__notion-search` with `query_type`: `user`, `query`: `name`.
2. Return the first matching user's ID, or `null` if no match.
3. Caveat: only workspace members are resolvable; external collaborators return `null`.

### `create_entry(properties, body) → entry_url`

Call `mcp__claude_ai_Notion__notion-create-pages` with a single page in `pages`:

- `parent`: `{ "data_source_id": "<DSID>" }`
- `properties`: object mapping each **live Notion property name** to its value. Property names come straight from the skill's payload (built against the cached schema). Include `Status` (or its equivalent) only when the skill provided it — the skill is responsible for picking `status_default` or a template-explicit override. The skill is also responsible for filtering out read-only Notion types (`formula`, `rollup`, `created_time`, `last_edited_time`, `relation`) per the skill's workflow step 5.2 — the adapter writes whatever the skill provides without re-filtering.
- `content`: the rendered body markdown (Notion MCP accepts enhanced markdown and converts to blocks).

For multi-select properties: the skill may include free-form values that don't exist as options on the board (typically because the user picked `Other` in the enum-miss prompt or a template carried a non-existing option). Notion auto-creates new options on the fly — the adapter passes them through without filtering. The skill is responsible for normalizing (lowercase, trim) before write to prevent typos becoming permanent options.

Return the created page's URL from the response.

### `update_entry(entry_id, properties, body) → entry_url`

1. Call `mcp__claude_ai_Notion__notion-update-page` with:
   - `page_id`: `entry_id`
   - `command`: `update_properties`
   - `properties`: the new properties object — the skill omits `Status` (or its equivalent) so the adapter does not need to filter.
2. Call `mcp__claude_ai_Notion__notion-update-page` with:
   - `page_id`: `entry_id`
   - `command`: `replace_content`
   - `new_str`: the rendered body markdown
3. Return the page's URL.

### `append_to_body(entry_id, body_fragment) → entry_url`

1. Call `mcp__claude_ai_Notion__notion-update-page` with:
   - `page_id`: `entry_id`
   - `command`: `insert_content`
   - `content`: `body_fragment`
   - `position`: `{ "type": "end" }`
2. Properties untouched.
3. Return the page's URL.

## 6. Body rendering notes

Notion MCP's `notion-create-pages` and update operations accept enhanced markdown directly. The body template's markdown is written verbatim — Notion handles the conversion to blocks. The HTML comment line `<!-- AI-drafted, {date} -->` is preserved by Notion as a hidden text block; expected.

**Brace escaping in templates.** Notion's MCP serializes literal `{` and `}` characters inside page bodies as `\{` and `\}` when returned from `notion-fetch`. This affects `fetch_schema()`'s `templates[i].body_markdown`: a template whose Notion source reads `{Why summary}` arrives at the skill as `\{Why summary\}`. The skill's placeholder substitution (workflow step 6.1) handles this with a backslash-unescape pre-pass in [`../placeholders.md`](../placeholders.md) before detection runs. Adapters do not need to do anything special; the unescape lives skill-side so the rule is uniform across backends. On write-back, plain `{` / `}` characters in the body are accepted by `notion-create-pages` without further intervention — Notion treats them as literal text.

If a future adapter (Affine, local-file, etc.) does NOT escape braces on read, the unescape pre-pass is a no-op against that body. The pre-pass is idempotent.

## 7. Known limitations

- **Status default fires on create when omitted** — Notion sets a default `Status` if none is provided in the payload. The skill always provides `Status` explicitly (either `status_default` from the schema or a template-explicit override), so the adapter does not need to compensate.
- **Multi-select auto-creates options** — Notion creates new multi-select options on the fly when the skill writes an unknown value. Useful for free-form project tags and for template-carried tags that don't pre-exist on the board; risky for typos. Skill normalizes before write (lowercase, trim, hyphenate spaces). Note: when a workspace admin has enabled stricter option enforcement (rare), the create / update call rejects the unknown value with a 400. Surface that error verbatim; the user can either add the option in the Notion UI or pick from existing ones on the next capture.
- **Eventual consistency** — Newly-created pages may not appear in `notion-search` for 1–5 seconds. Within a single invocation, prefer storing the just-created page ID over re-searching.
- **Person resolution scope** — Only workspace members. External @-mentions, deleted users, and guests return `null`.
- **Rate limits** — Notion API allows ~3 requests/sec sustained. Per-capture call budget:
  - source-side fetch (workflow step 2): 0–1 calls (skipped for Paper/Idea/Conversation/Other)
  - 1-hop enrichment (workflow step 3): 0–1 calls
  - `fetch_schema()` (workflow step 0.5): 1 database fetch + M template fetches, **once per session** (cached)
  - dedupe (workflow step 4 via `search_by_source_url`): 2 calls on a hit (search + 1 fetch via short-circuit); 1 + N on a miss (N ≤ 5)
  - board write (workflow step 7): 1 call

  First capture in a session: 5–8 calls (schema fetch dominates). Subsequent captures in the same session: 3–4 calls (schema cached). Worst case ~12. Well within 3 req/sec for any realistic burst; back off 1 second between captures if burst-capturing more than 2 todos.
- **Schema discovery depends on MCP version.** If the active Notion MCP doesn't surface templates in its `notion-fetch` response, `fetch_schema()` returns `templates: []` and the skill falls back to the standard body render. No degradation beyond pre-templates behavior.
- **Template `@mentions` and database refs.** Notion templates can contain `@mentions`, sub-page references, and inline database views. These are preserved verbatim in the copied markdown. Notion typically re-resolves them on paste; if not, the references stay as plain text — the user can fix manually.
- **Body replace is a single operation** — `update_entry`'s body-replace uses `replace_content`, one call, so there is no partial-failure window between separate fetch/delete/create steps.

## 8. Migration notes

To migrate off Notion as the active backend:

1. Author a new adapter file `<vendor>.md` in this directory following the contract in [`README.md`](README.md).
2. Export existing Notion entries to the new backend. Out of skill scope — common approaches:
   - Use Notion's built-in CSV export and a one-shot import script for the target backend.
   - Iterate `mcp__claude_ai_Notion__notion-query-data-sources` (queried via the `collection://<DSID>` data-source URL derived per section 2) + the target backend's create API for a programmatic migration.
3. Edit `Active backend → Adapter:` in [`../../SKILL.md`](../../SKILL.md) to point at the new file.
4. Edit `~/.config/quick-capture/config.json`: flip `active_backend` to the new name, replace `board_ref` with the new backend's URL. `locale` carries over.
5. Run the new backend's `First-run setup` if it hasn't been triggered yet (typically: just delete the config and let the skill re-prompt).

The skill core, logical property model, body template do not change.
