---
name: onboard-to-marketplace
description: Use when the user wants to bring an external Claude Code plugin folder, or an individual skill folder, into the agentic-kelzenberg marketplace at this repo. Triggers include "onboard this plugin", "onboard this skill", "import this skill", "move plugin X into the marketplace", "copy this skill into agentic", "add a skill to way-of-working", "drop this skill into plugin X", "add a new plugin to agentic-kelzenberg", or when the user hands over a path to an external plugin/skill they want to publish here.
---

# Onboard to marketplace

Bring an external **plugin** folder or an external **skill** folder into this repo's `agentic-kelzenberg` marketplace. Copy or move the source in, scrub PII, polish files to repo standard, register where needed, then stop before staging — the user runs their own commit flow.

Two onboarding modes:

- **`plugin` mode** — source becomes a new plugin under `claude/plugins/<name>/`. Manifest gets a new entry. Root README catalog gets a new bullet.
- **`skill` mode** — source becomes an additional skill inside an existing plugin's `skills/` folder. No manifest edit (skills auto-discover). Root README bullet for the host plugin may be extended with the new skill link (with user confirmation).

## Inputs (gather once, then proceed)

| Input | Required | Notes |
|---|---|---|
| Source path | yes | Absolute path to either a bare skill folder (contains `SKILL.md`) or a wrapped plugin folder (contains `.claude-plugin/plugin.json`). |
| Onboarding mode | yes | `plugin` or `skill`. Determined per §1. |
| Operation | yes | `copy` (keeps source) or `move` (removes source after success). `add` is an alias for `copy`. |
| Host plugin | when mode = `skill` | Picked from `.claude-plugin/marketplace.json` `plugins[]`. |
| Target plugin name | when mode = `plugin` | Kebab-case, 2–4 words. Default for wrapped source = source folder basename; required for bare-skill wrap. Always ask to confirm/rename. |
| Target skill folder name | when mode = `skill`, or when wrapping a bare skill | Default = source folder basename. Always ask to confirm/rename. |
| One-line description | when source has none and mode = `plugin` | For the marketplace entry. |

## Workflow

### 1. Inspect source and classify intent

Read source folder structure. Classify shape:

- **Wrapped plugin** — has `.claude-plugin/plugin.json` plus one of `skills/`, `commands/`, `agents/`, `hooks/`, `.mcp.json`. Mode = `plugin`. No question.
- **Bare skill** — contains `SKILL.md` (and optional `examples/`, `scripts/`, etc.); no `.claude-plugin/`. **Ask the user** via `AskUserQuestion`:

  > "Wrap as a new plugin in the marketplace, or add to an existing plugin's skills/ folder?"

  - `plugin` answer → wrap as a new plugin.
  - `skill` answer → add to an existing plugin.

- Neither shape → refuse (§Refuse if).

### 2. Resolve target

**Mode = `plugin`:**

- Default target plugin folder name = source basename. Ask user to confirm or override (single text input, default pre-filled).
- Refuse on collision under `claude/plugins/` or in `.claude-plugin/marketplace.json`.
- For bare-skill wrap: also ask for the skill folder name to use under `skills/` (default = source basename).
- If source `plugin.json` lacks a description, ask the user for a one-line description.

**Mode = `skill`:**

- Read `.claude-plugin/marketplace.json`. Present `plugins[]` as a list (name + description) via `AskUserQuestion`. User picks the host plugin.
- Verify host plugin folder exists at `claude/plugins/<host>/`. If listed but missing on disk → refuse with diagnostic.
- Default skill folder name = source basename. Ask user to confirm or override.
- Refuse on collision under `claude/plugins/<host>/skills/`.

### 3. Copy or move bytes to target

**Mode = `plugin`, wrapped source** → `cp -r` (copy) or `mv` (move) whole folder to `claude/plugins/<plugin-name>/`. Rename top-level dir if the user picked a different name.

**Mode = `plugin`, bare-skill source** → wrap as a new plugin:

```
claude/plugins/<plugin-name>/
├── .claude-plugin/plugin.json        ← synthesized: name + description + author.name=kelzenberg
└── skills/<skill-folder-name>/...    ← the source folder, contents intact
```

**Mode = `skill`** → `cp -r` (copy) or `mv` (move) the source folder to `claude/plugins/<host>/skills/<skill-folder-name>/`. Do not create or edit `plugin.json`. Do not touch other skills under that `skills/`.

Use `cp -r` for copy, `mv` for move. After `mv`, leave the source's parent dir untouched.

### 4. Scrub PII

Apply the canonical patterns, allowlist (tier 1 + tier 2), and placeholder vocabulary defined in [`../../references/pii-policy.md`](../../references/pii-policy.md). Scope = the imported subtree only (the new plugin folder, or the new skill folder — **not** the whole repo).

Workflow:

1. Run the scanner: `../../scripts/pii-scan.sh --scope <imported-subtree>` (from this skill's directory; use `${CLAUDE_PLUGIN_ROOT}/scripts/pii-scan.sh` when installed as a plugin). Its enumerator covers untracked files, so the freshly copied source is scanned without staging first.
2. Classify each `HIT`/`CAND` line as auto-scrub or borderline per the policy.
3. Auto-scrub: apply the placeholder replacement; show a unified diff per file.
4. Borderline: present a single batched list with a keep / scrub choice per item.
5. Re-run the scanner after edits to confirm zero `HIT` lines remain.

For repo-wide scans outside the onboarding flow (e.g., before commit / PR), use the `check-pii` skill instead.

### 5. Polish to repo standard

Compute target edits per imported file. Scope = imported subtree only.

**Markdown files (`*.md`):**
- Skip the `SKILL.md` frontmatter; everything below is in scope.
- Prepend `<!-- AI-drafted, YYYY-MM-DD -->` (today's ISO date) as the first line if absent — except Markdown files whose first bytes must be YAML frontmatter (`SKILL.md`, `commands/*.md`, `agents/*.md`), and by established practice across this repo's plugins those files carry no marker.
- Replace bare autolinks `<https://...>` with `[label](url)` form when a label is recoverable from nearby prose; otherwise leave.
- Trim trailing whitespace; ensure single trailing newline.

**JSON files (`*.json`):**
- Validate via `jq` — abort if any file fails to parse.
- Re-emit with `jq --indent 2 .` for consistent formatting.
- Strip `author.email` and `owner.email` if present.
- Strip `version` field if present (this marketplace uses git SHA versioning).

Show a unified diff per file. Ask user to confirm apply or skip per file. Default: apply.

### 6. Register

**Mode = `plugin`** → append an entry to `plugins[]` in `.claude-plugin/marketplace.json`:

```json
{
  "name": "<plugin-name>",
  "source": "./claude/plugins/<plugin-name>",
  "description": "<one-line description from plugin.json>"
}
```

After append, sort `plugins[]` alphabetically by `name` for stable diffs.

**Mode = `skill`** → **skip this step.** Skills auto-discover under their host plugin. Note in the report (§9) which host plugin received the skill.

### 7. Update repo-root `README.md` plugin catalog

The `## Plugins` section in `README.md` (repo root) is the human-facing catalog.

**Mode = `plugin`** → append a bullet for the new plugin:

```markdown
- **[`<plugin-name>`](claude/plugins/<plugin-name>/)** — <one-line description>.
```

Insert in alphabetical order to match `marketplace.json`'s sort.

**Mode = `skill`** → find the host plugin's existing bullet. Compute a minimal extension that adds a `[<skill-name>](<skill-path>)` link with a short trailing phrase inside the existing sentence. Show the unified diff. Ask user to confirm — skip on decline. Do not rewrite the whole bullet; do not reorder other bullets.

### 8. Verify

All checks must pass; abort with diagnostic if any fail.

**Common (both modes):**
- Re-run the same scanner invocation from §4 (`../../scripts/pii-scan.sh --scope <imported-subtree>`, or `${CLAUDE_PLUGIN_ROOT}/scripts/pii-scan.sh --scope <imported-subtree>` when installed) against the imported subtree. Verification = exit code `0` and zero `HIT` lines in the output.
- Each `SKILL.md` under the imported subtree has valid YAML frontmatter with at least `name` and `description` fields.

**Mode = `plugin` additionally:**
- `jq . .claude-plugin/marketplace.json` parses, contains the new entry, `plugins[]` is alphabetically sorted by `name`.
- `jq . claude/plugins/<plugin-name>/.claude-plugin/plugin.json` parses, contains required `name`.
- Spec compliance: only `.claude-plugin/plugin.json` lives inside the plugin's `.claude-plugin/`; content dirs (`skills/`, `commands/`, `agents/`, `hooks/`, `references/`, `scripts/`) sit at the plugin root, one level deep.

**Mode = `skill` additionally:**
- Skill landed at `claude/plugins/<host>/skills/<skill-folder-name>/` — not nested under a grouping subdir.
- Host plugin's `.claude-plugin/plugin.json` is unchanged compared to `HEAD` (no accidental edit).
- `marketplace.json` is unchanged compared to `HEAD`.

### 9. Report and stop

Print a summary:

```
Onboarded: <plugin-or-skill-name> (mode: plugin|skill, op: copy|move)
Target:    <claude/plugins/...>
Host:      <host-plugin>            ← skill mode only
Source:    <source-path>
Files:     <count> created, <count> modified, <count> polished
Scrub:     <count> auto-scrubs, <count> kept after user review
Manifest:  appended; <total> plugins total   ← plugin mode
           skipped — skills auto-discover    ← skill mode
Catalog:   README.md updated                 ← plugin mode
           README.md bullet extended         ← skill mode (if confirmed)
           skipped                           ← skill mode (if declined)
Next:      review `git status`, then run your commit flow.
```

Do NOT run `git add`. Do NOT run `git commit`. The user's commit flow picks up the `caveman-commit` skill on their own invocation, per the repo's CLAUDE.md no-auto-commit rule.

## Repo-standard reference

These conventions are derived from the existing files at the time of writing. If repo standards drift, update this skill to match.

- **Markdown prose:** AI-drafted marker as the first line of any file this repo authors (`<!-- AI-drafted, YYYY-MM-DD -->`) — any Markdown file whose first bytes must be YAML frontmatter is exempt (`SKILL.md`, `commands/*.md`, `agents/*.md`; frontmatter stays first, and no sibling file of those kinds carries one), `[label](url)` link form (no bare autolinks), terse imperative bullets, fenced code blocks, kebab-case identifiers.
- **Plugin manifest (`plugin.json`):** `name` + `description` required. `author.name` only — no `author.email`. Never include a `version` field — git SHA drives versioning.
- **Marketplace entry:** `name` + `source` + `description`. `source` uses `./claude/plugins/<plugin-name>`. Entries sorted by `name`.
- **Plugin layout:** Only `plugin.json` in `.claude-plugin/`. Content directories (`skills/`, `commands/`, `agents/`, `hooks/`, `references/`, `scripts/`, `.mcp.json`) at plugin root. Skill folders directly under `skills/` — no grouping subdirs (Claude Code only discovers one level deep).
- **Root catalog:** Root `README.md` has a `## Plugins` section with one bullet per plugin, alphabetically ordered.

## Refuse if

- Source path does not exist or is unreadable.
- Source matches neither bare-skill nor wrapped-plugin shape.
- Mode = `plugin` and target plugin name collides with an existing folder under `claude/plugins/` or an existing entry in `marketplace.json`.
- Mode = `skill` and target skill folder name collides with an existing folder under `claude/plugins/<host>/skills/`.
- Mode = `skill` and `marketplace.json` lists no plugins (nothing to host the skill).
- Mode = `skill` and the chosen host plugin is listed in `marketplace.json` but its folder is missing from disk (stale manifest — tell the user, stop).
- Working tree has unrelated staged changes — warn the user and let them decide whether to proceed (the onboarding writes touch multiple files; a clean tree makes rollback trivial).

## Anti-patterns

- Auto-staging or auto-committing — both forbidden by repo CLAUDE.md.
- Editing `LICENSE`.
- Scrubbing items from the auto-keep allowlist.
- Adding a `version` field to `plugin.json`.
- Creating grouping subdirs under `skills/` (Claude Code skill discovery is one level deep).
- Renaming the imported skill folder without user consent.
- Reformatting files outside the imported plugin/skill's tree.
- Mode = `skill`: creating a `plugin.json` inside the host plugin's `skills/` folder (skills carry no manifest).
- Mode = `skill`: editing the host plugin's `plugin.json` (skills auto-discover; nothing to register).
- Mode = `skill`: re-sorting or re-authoring the host plugin's README catalog bullet beyond the targeted extension.
- Silently picking `plugin` mode for a bare-skill source (the user may want to add a skill to an existing plugin — always ask).
- Inlining a reduced copy of the scan patterns anywhere — the script is the single scanner; invoke it.
