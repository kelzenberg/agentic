<!-- AI-drafted, 2026-06-03 -->

# Claude Code instructions for this repo

This repo (`agentic-kelzenberg`) is a public Claude Code plugin marketplace. Same hard rules apply as in [`AGENTS.md`](AGENTS.md); read [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full policy.

## Hard rules

- **Add plugins / skills only via [`onboard-to-marketplace`](claude/plugins/marketplace-curator/skills/onboard-to-marketplace/SKILL.md).** Single entry point. Never hand-create plugin folders, manifest entries, or root README bullets.
- **No PII, no private URLs, ever.** Patterns + allowlist + placeholders in [`claude/plugins/marketplace-curator/references/pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md). Applies to files, memory, plans, commits, PRs.
- **Allowlist** = `kelzenberg` / `agentic-kelzenberg` / `agentic` (LICENSE — always keep), `Anthropic` / `Claude` / `Claude Code`, plus current `owner.name` + `name` from [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).
- **Placeholders**: vocabulary = auto-scrub table in [`pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md). Single source, not restated here.
- **Before commit / push / PR**: invoke the [`check-pii`](claude/plugins/marketplace-curator/skills/check-pii/SKILL.md) skill (runs `claude/plugins/marketplace-curator/scripts/pii-scan.sh`, canonical patterns source). Stop on hits. Pre-commit hook + CI run same script.
- **Do not invent URLs.** Only commit URLs the user provided AND that you have verified are public.
- **AI-drafted marker** as first line of any new Markdown file: `<!-- AI-drafted, YYYY-MM-DD -->`.
- **No auto-stage, no auto-commit.** The user runs their own commit flow (the `caveman-commit` skill, if loaded, picks up on their invocation).

When uncertain, ask the user before persisting.

## Commit and PR style

- Use the user's loaded `*-commit` skill (e.g., `caveman-commit`) when generating commit messages. Do not hand-write commit messages when a commit-message skill is loaded.
- US English everywhere. ISO dates (`YYYY-MM-DD`) in code, filenames, commits, and AI-drafted markers.
