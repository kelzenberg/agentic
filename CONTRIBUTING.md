<!-- AI-drafted, 2026-06-03 -->

# Contributing

`agentic-kelzenberg` is a public Claude Code plugin marketplace. Anyone can install the plugins or fork the repo. Direct contributions (branches, pull requests) are currently limited to invited collaborators — this may open up in the future. Until then, external suggestions are welcome as GitHub issues. Two rules govern everything below:

1. **All contributions go through the `onboard-to-marketplace` skill** (single entry point for adding plugins and skills — see below).
2. **Zero personal identifying information (PII) and zero links to personal / company-private content end up committed.** This applies to humans and AI agents equally.

If you cannot satisfy both, do not commit.

## Adding a plugin or skill

Use the [`onboard-to-marketplace`](claude/plugins/marketplace-curator/skills/onboard-to-marketplace/SKILL.md) skill from the [`marketplace-curator`](claude/plugins/marketplace-curator/) plugin. It is the **single entry point** for bringing new content into this marketplace. It handles:

- Folder placement under `claude/plugins/<plugin>/` or `claude/plugins/<host>/skills/<skill>/`.
- Manifest registration in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).
- Root [`README.md`](README.md) catalog updates.
- PII scrubbing per the policy below.
- Stopping before staging so your commit flow stays in your control.

Do NOT hand-author plugin folders or marketplace entries from scratch. If onboarding is missing a feature you need, raise an issue first. (Non-collaborators: an issue is also the right channel for proposing a plugin or skill while direct contributions are collaborator-only.)

## Editing existing files

When changing files already in the repo (plugin sources, READMEs, manifest, this file), the PII rules below still apply. Run the [`check-pii`](claude/plugins/marketplace-curator/skills/check-pii/SKILL.md) skill before committing — the pre-commit hook (see Enforcement below), once enabled, automatically runs the mechanical scanner over staged changes, but it does not replace the skill's semantic read pass.

## PII and private content — mandatory for humans and AI agents

This repo is public. Plugins, skills, examples, fixtures, comments, READMEs, and commit / PR messages must contain **zero** PII and **zero** URLs or paths to personal or company-private content.

The canonical patterns, allowlist, and placeholder vocabulary live in [`claude/plugins/marketplace-curator/references/pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md). Summary below.

### Allowlist

Always permitted, everywhere (LICENSE-required attribution — do NOT remove on forks):

- `kelzenberg`, `agentic-kelzenberg`, `agentic`
- `Anthropic`, `Claude`, `Claude Code`

Additionally permitted = the current `owner.name` and `name` fields in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Forks add their own handle / marketplace name by updating that one file; guidance docs do not need to change.

### Never commit

- Email addresses (yours, colleagues, customers, vendors).
- Real names not on the allowlist.
- Absolute filesystem paths — anything under `/Users/`, `/home/`, or `C:\Users\`, plus tilde and Windows profile-variable forms.
- Internal hostnames, IPs, VPN endpoints, private API URLs.
- URLs to private Notion / Linear / Jira / Slack / Asana / Confluence / company wikis / internal dashboards / employer websites. See the full known-private-host list in [`pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md).
- Customer or vendor names tied to private engagements.
- Screenshots of private content.
- Anything under `.claude/settings.local.json`, `.env*`, or paths in `.gitignore`.

### Always

- Use the placeholder vocabulary from [`pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md)'s auto-scrub table — that table is the single source, so this doc does not restate it.
- Prepend `<!-- AI-drafted, YYYY-MM-DD -->` to AI-authored Markdown files.
- Before each commit, push, or PR: invoke the `check-pii` skill. It runs the canonical scanner script (`claude/plugins/marketplace-curator/scripts/pii-scan.sh`) — that script is the single source of truth for the scan patterns, not a copy in this doc.

### Enforcement

- **Pre-commit hook** (one-time local setup): `git config core.hooksPath .githooks` points git at [`.githooks/pre-commit`](.githooks/pre-commit), which runs the scanner against staged files before every commit and blocks the commit on any hit. A deletion-only commit passes (nothing to read is reported, not an error), but `git commit --allow-empty` is blocked by design: an empty index gives the gate nothing to verify, and a safety gate fails closed.
- **CI**: [`.github/workflows/pii-scan.yml`](.github/workflows/pii-scan.yml) runs the same scanner (self-test plus a full-tree scan) on every push and pull request; the check must pass before merge.
- **LICENSE**: never auto-edited by the scanner or by scrubbing. The scanner reports the file's copyright line on every run for explicit human confirmation, rather than silently skipping it.

### AI agents specifically

- Do NOT save PII or private URLs to memory files, plan files, scratchpads, test fixtures, example code, doc strings, comments, commit messages, or PR descriptions.
- If a user pastes private content while authoring a skill, ask before persisting — propose a placeholder.
- Do NOT invent URLs. Only commit URLs the user has explicitly provided AND that are verified public.
- Read [`AGENTS.md`](AGENTS.md) (or [`CLAUDE.md`](CLAUDE.md) for Claude Code) for the agent-side summary of these rules.

## Forking

You may fork freely under the repository LICENSE. When you do:

1. Update `owner.name` and `name` in `.claude-plugin/marketplace.json` to your own handle and marketplace name.
2. Keep the tier-1 attribution literals (`kelzenberg`, `agentic-kelzenberg`, `agentic`) wherever they appear — the LICENSE requires preserving original authorship. They are part of the permanent allowlist.
3. Everything else (`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `pii-policy.md`, the `check-pii` skill) works as-is without further edits.

## Commit flow

This repo does not auto-stage or auto-commit. After running `onboard-to-marketplace` or `check-pii`, review `git status` and run your own commit flow.
