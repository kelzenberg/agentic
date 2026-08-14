<!-- AI-drafted, 2026-05-22 -->

# agentic

[Claude Code](https://code.claude.com/docs/) plugin marketplace — plugins and skills by [@kelzenberg](https://github.com/kelzenberg).

## Install

```bash
/plugin marketplace add kelzenberg/agentic
/plugin install <plugin-name>@agentic-kelzenberg
```

## Plugins

- **[`marketplace-curator`](claude/plugins/marketplace-curator/)** — tools for curating this marketplace. Ships with [`onboard-to-marketplace`](claude/plugins/marketplace-curator/skills/onboard-to-marketplace/SKILL.md), which copies or moves either an external plugin folder into [`claude/plugins/`](claude/plugins/) — registering it in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) — or an individual skill folder into an existing plugin's `skills/` directory (skills auto-discover, so no manifest edit). Either way it scrubs PII, polishes imported files to this repo's standard, and stops before staging so the commit flow stays under user control. Also ships [`check-pii`](claude/plugins/marketplace-curator/skills/check-pii/SKILL.md), an on-demand scan invoked before commit / push / PR that audits the repo (or a subtree) against the shared policy in [`references/pii-policy.md`](claude/plugins/marketplace-curator/references/pii-policy.md) and reports any leaks.
- **[`quick-capture`](claude/plugins/quick-capture/)** — quickly capture todos onto a personal task board from any input. Ships [`capture-todo`](claude/plugins/quick-capture/skills/capture-todo/SKILL.md), which parses URLs / paragraphs / paper-note transcriptions / freeform thoughts, performs bounded enrichment ("source + 1 hop") via the available connectors, dedupes against existing entries, and writes a concise entry with structured properties and a deep-linked body — plus the [`/personal-todo`](claude/plugins/quick-capture/commands/personal-todo.md) slash command for explicit invocation. The board backend is swappable: all vendor-specific details live in a single adapter file under [`skills/capture-todo/references/backends/`](claude/plugins/quick-capture/skills/capture-todo/references/backends/), with [Notion](claude/plugins/quick-capture/skills/capture-todo/references/backends/notion.md) as the active backend.
- **[`way-of-working`](claude/plugins/way-of-working/)** — capture and host reusable collaboration patterns for Claude Code sessions. Ships [`extract-way-of-working`](claude/plugins/way-of-working/skills/extract-way-of-working/SKILL.md), the meta-skill that writes each extracted pattern as a sibling subdirectory under [`claude/plugins/way-of-working/skills/`](claude/plugins/way-of-working/skills/), alongside [`sparring-partner`](claude/plugins/way-of-working/skills/sparring-partner/SKILL.md), a principle-engineering / architecture sparring mode for fuzzy-edged multi-step projects, [`root-cause-first`](claude/plugins/way-of-working/skills/root-cause-first/SKILL.md), an investigation-first debugging discipline that demands a reproducible root cause before any fix, and [`guided-ux-walkthrough`](claude/plugins/way-of-working/skills/guided-ux-walkthrough/SKILL.md), a paced live-browser review mode that presents changes step-by-step for the user's judgment and collects their remarks without acting on them mid-pass. Any new skill dropped under that `skills/` path ships with the plugin automatically — no manifest edits required.

## Repo layout

- [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) — marketplace manifest.
- [`claude/`](claude/) — plugin source folders. See [`claude/README.md`](claude/README.md) for how to author and add new plugins.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution flow and the mandatory PII / public-safety rules. AI agents should additionally read [`AGENTS.md`](AGENTS.md) — or [`CLAUDE.md`](CLAUDE.md) if running under Claude Code — both of which restate the hard rules in agent-friendly form.

## Reference

- [Claude Code plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Claude Code plugins](https://code.claude.com/docs/en/plugins.md)
