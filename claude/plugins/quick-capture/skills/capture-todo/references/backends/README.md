<!-- AI-drafted, 2026-06-09 -->

# Backend adapters

The `capture-todo` skill is backend-agnostic. Every interaction with the personal task board goes through a single **active backend adapter** named at the top of [`../../SKILL.md`](../../SKILL.md). The adapter encapsulates everything vendor-specific: how to read the live schema, search syntax, write operations, MCP tool names, rate-limit notes, and how to derive any runtime identifiers from the `board_ref` in local config.

The skill core (workflow, logical property model, body template) does not change when the active backend changes.

## Principle

The adapter is a **thin, stateless bridge** between the skill's logical operations and the backend's MCP tools. It does not:

- Maintain a persisted translation layer (no aliases on disk).
- Cache schema across captures (the skill caches once per session; adapters reference that same cached schema in-context for type-filtered live-property lookups, e.g. `search_by_source_url`, but never maintain their own cache).
- Validate the schema against a hardcoded shape at setup time (the board's schema is whatever it is).
- Hold any user-specific value in this file (URLs, IDs, workspace names — all derived from `board_ref` at runtime).

The adapter operates exclusively in **live property names** as they currently exist on the board. The skill discovers those names via `fetch_schema()` and passes them back on every write.

## Swapping the active backend

1. Drop in a new adapter file (`<vendor>.md`) under this directory following the contract below.
2. Flip the `Active backend → Adapter:` line in [`../../SKILL.md`](../../SKILL.md) to point at it.
3. The user runs the new adapter's first-run setup once. The skill picks up the new backend transparently.

There is exactly **one** source of truth for "what backend is live right now" — that single line in `SKILL.md`. Don't duplicate the pointer elsewhere.

## Adapter contract

Every adapter file must answer these sections in this order. Skipping or merging sections is not allowed — the skill expects to find each one by heading.

### 1. `Identity`

A short table naming the vendor and stating what shape of `board_ref` the adapter accepts. No user-specific values appear in this section.

### 2. `Local config`

The local config holds exactly three top-level fields (`active_backend`, `board_ref`, `locale`); see [`../../SKILL.md`](../../SKILL.md) for the canonical skeleton. Adapter-specific configuration is **not** supported. There is no `backends.<name>` sub-block. Any runtime identifier (database ID, data source ID, project key, OAuth scope) that an adapter needs is derived from `board_ref` or fetched live at session start; nothing extra is persisted.

This section documents:

- The exact `board_ref` shapes the adapter accepts (e.g. accepted Notion URL formats).
- How runtime identifiers (database IDs, data source IDs, project keys, etc.) are derived from `board_ref` at session start. These derived values are **never** persisted; they are recomputed each session.

File location and permission notes are the same for every backend — see [`../../SKILL.md`](../../SKILL.md) instead of repeating them per adapter.

### 3. `First-run setup`

The flow the skill runs when `~/.config/quick-capture/config.json` is missing.

Three setup questions plus a write-confirmation prompt (four `AskUserQuestion` calls) and one access check. The board's schema **shape** is not validated here (no required-column check, no enum-option check) — the workflow's session-start `fetch_schema()` handles whatever shape the board carries.

Steps:

1. **Backend pick.** Single-select `AskUserQuestion` listing the available adapters (today: just the active one). Skip when only one adapter exists and `active_backend` is implied.
2. **Board reference.** One `AskUserQuestion` with the accepted shapes described as the option label / description. The user pastes the URL via the implicit `Other` free-text fallback.
3. **Locale.** Single-select `AskUserQuestion` with options `YYYY-MM-DD (ISO)`, `DD.MM.YYYY (European)`, `MM/DD/YYYY (US)`.
4. **Verify access.** Make one read call against the backend (typically `fetch_schema()` itself, or a minimal "ping the board" call) to confirm the user's credentials reach the board. This call only checks reachability and auth; the returned schema-shape is not asserted against any hardcoded expectation. On failure, re-prompt the board-reference question via `AskUserQuestion` (`Re-paste URL` / `Abort`).
5. **Confirm write.** One `AskUserQuestion` (`Yes, write config` / `No, abort setup`) before writing the file.
6. **Write the config file.** `mkdir -p` the directory first; restrict file mode where the OS supports it (`chmod 600` on Unix).
7. **Confirm success** with a one-line plain-text summary. Do not name the vendor.

There is no schema-shape validation at setup. Setup records only the pointer; the board's schema is queried on every capture and the workflow adapts to whatever exists. After step 7 the workflow continues with step 0.5 (schema discovery) and the original capture proceeds.

### 4. `Schema discovery`

How `fetch_schema()` is implemented for this backend. The returned object's shape is fixed and identical across backends:

```
{
  properties:     [{ name, type, options? }, …],
  templates:      [{ id, name, body_markdown, property_defaults }, …],
  status_default: "<first option of the Status-typed property, or null>",
}
```

- `properties[i].name` is the **live** name as it appears on the board today.
- `properties[i].type` is a normalized logical type — one of `title`, `text`, `select`, `multi_select`, `status`, `date`, `url`, `person`, `created_time`, `updated_time`, `formula`, `relation`, `unknown`. Adapters translate the backend's native types into this set so the skill doesn't need vendor knowledge.
- `properties[i].options` is present only for `select` / `multi_select` / `status` types and contains the live list of option names.
- `templates[i].property_defaults` is a partial map of **live property names → live values** (matching what the backend actually carries on the template page). Only include properties the template explicitly carries; omit empty / unset ones.
- `status_default` is the first option of the `status`-typed property if one exists; `null` otherwise.

`fetch_schema()` must **never throw**. On error (auth, network, malformed response) return an object with `properties: []`, `templates: []`, `status_default: null`, plus an `error: "<one-line message>"` field that the skill detects to drive user-facing surfacing. The skill (not the adapter) is responsible for displaying errors to the user and offering re-setup via `AskUserQuestion`. The adapter is responsible for never raising.

### 5. `Operations`

Documented implementations (prose + the exact MCP tool name or CLI command) of every operation listed in `SKILL.md`'s `Active backend` section:

- `fetch_schema() → { properties, templates, status_default }` — described in section 4. Required.
- `search_by_source_url(url) → entry | null` — the adapter looks for a URL-typed property whose live name best matches "Source URL" by applying the [matching tier sequence](../matching.md) (filtered to `url`-typed candidates). If no URL-typed property exists, returns `null` without error.
- `search_by_title_similarity(title) → [entry, …]` — search by title text; returns up to 3 candidates scored by token overlap. Backend-specific search syntax goes here.
- `resolve_person(name) → person_ref | null` — optional. If the backend has no person directory, mark "not implemented" and always return `null`.
- `create_entry(properties, body) → entry_url` — `properties` is keyed by **live property names** as returned from `fetch_schema()`. The skill builds this payload; the adapter does not translate.
- `update_entry(entry_id, properties, body) → entry_url` — same payload contract. The skill omits `Status` (or its equivalent) from the payload on updates (user-owned).
- `append_to_body(entry_id, body_fragment) → entry_url` — append-only body operation, no property writes.

For each: the exact tool call(s), the input shape, the output shape, expected error modes, and any vendor-specific quirks. Every reference to a board ID, data source ID, workspace, or URL resolves at runtime from `board_ref` — adapter files **never** contain user-specific values.

**Template body is raw.** `fetch_schema()` returns `templates[i].body_markdown` verbatim as it lives on the backend — including any `{placeholder}` text the user put in their template. The skill's step 6.1 handles placeholder substitution after the adapter returns. Adapters do **not** substitute placeholders themselves.

### 6. `Body rendering notes`

If the backend's body format diverges from standard markdown (block-based editors, custom rich-text formats), describe the translation rules here. The default assumption is that the adapter accepts the [`../body-template.md`](../body-template.md) markdown verbatim.

### 7. `Known limitations`

Anything the user should know about this backend — feature gaps, race conditions, rate limits, person-resolution scope, search consistency, template-discovery quirks tied to MCP server versions. Helps when choosing a backend.

### 8. `Migration notes`

How to leave this backend: what data needs to be exported, where the cutover happens, and how the user updates their local config (`active_backend` + `board_ref`) to point at the new backend. Out-of-scope mechanics (manual export, scripted migration) should be flagged but not invented.

## Don't put in the adapter

- **Trigger phrases** for the skill — those live in `SKILL.md` frontmatter and are vendor-neutral.
- **The body template** — that lives in [`../body-template.md`](../body-template.md).
- **Inference rules** for property values from user input — those live in [`../property-model.md`](../property-model.md).
- **A hardcoded list of expected board properties** — the board's schema is whatever it is on the day of capture. The adapter discovers; it does not declare.
- **A property-name translation map** — the skill matches logical fields to live property names at runtime via the LLM. No persisted aliases.
- **Any user-specific value** — URLs, IDs, workspace names, locale. The user-specific pointer lives in `~/.config/quick-capture/config.json`; everything derivable from it is computed each session.
- **Source-side write operations** — adapters describe board-side operations only. The skill never writes anything back to source surfaces (no backlink comments, no mentions).

The adapter is the **vendor boundary** for the board only. Anything that does not depend on the board vendor stays out. Anything that depends on the *user* lives in local config, not the adapter file. Anything that depends on the *current board schema* is discovered live, not declared.

## Enum-miss handling is a skill responsibility

When an inferred enum value (e.g. `Priority: High`) cannot be confidently matched to one of the live `options` returned by `fetch_schema()`, the **skill** fires an `AskUserQuestion` (see `SKILL.md` step 5.2). The adapter is not involved in this flow — it sees only the user's chosen live value on the eventual write. Adapters do not contain decision logic for ambiguous matches.

## Conventions for adapter files

- File name: `<vendor-name>.md` in kebab-case (e.g. `notion.md`, `affine.md`, `local-file.md`).
- Open with `<!-- AI-drafted, YYYY-MM-DD -->` on the first line, using ISO date.
- Use `[label](url)` markdown links — no bare URLs.
- Use sentence-case headings and the exact section names listed above.
- Operations are documented under their exact contract names as listed in [`../../SKILL.md`](../../SKILL.md)'s `Active backend` section — `fetch_schema`, `search_by_source_url`, `search_by_title_similarity`, `resolve_person`, `create_entry`, `update_entry`, `append_to_body`. Don't rename, don't merge, don't add.
- Keep prose terse. Operations sections should read like protocol specs, not tutorials.
