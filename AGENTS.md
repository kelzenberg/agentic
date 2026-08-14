<!-- AI-drafted, 2026-06-03 -->

# Agent instructions for this repo

This repo (`agentic-kelzenberg`) is a public Claude Code plugin marketplace. Before adding or editing any plugin, skill, command, agent, doc, or manifest here, read [`CONTRIBUTING.md`](CONTRIBUTING.md) — especially the **"PII and private content"** section.

## Hard rules (summary)

1. **Adding a new plugin or skill = use the [`onboard-to-marketplace`](claude/plugins/marketplace-curator/skills/onboard-to-marketplace/SKILL.md) skill.** Single entry point. Do NOT hand-create plugin folders, manifest entries, or README catalog bullets from scratch.
2. **Never write PII or links to personal / company-private content** to any file in this repo, to memory, plans, scratchpads, commit messages, or PR descriptions. The canonical policy (patterns, allowlist, placeholders, known private hosts) lives in [`claude/plugins/marketplace-curator/references/pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md).
3. **Allowlist** = `kelzenberg` / `agentic-kelzenberg` / `agentic` (LICENSE attribution — keep on all forks), `Anthropic` / `Claude` / `Claude Code`, plus the current `owner.name` and `name` in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Everything else is suspect.
4. **Use placeholders** when scrubbing — the vocabulary is the auto-scrub table in [`pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md); read it there rather than from a copy.
5. **Before commit, push, or PR**: invoke the [`check-pii`](claude/plugins/marketplace-curator/skills/check-pii/SKILL.md) skill from `marketplace-curator`. It runs the canonical scanner script (`claude/plugins/marketplace-curator/scripts/pii-scan.sh`) and reports hits; a pre-commit hook and CI run the same script automatically.
6. **Do not invent URLs.** Only commit URLs the user has explicitly provided AND that you have verified are public.
7. **AI-drafted marker.** Prepend `<!-- AI-drafted, YYYY-MM-DD -->` (today's ISO date) to any new Markdown file you author.
8. **No auto-staging or auto-committing.** The user owns the commit flow.

When unsure, ask the user before persisting.
