<!-- AI-drafted, 2026-05-22 -->

# `claude/` — Plugin content for the `agentic-kelzenberg` marketplace

Plugin source folders for the `agentic-kelzenberg` marketplace.
The marketplace manifest itself lives at the repo root: [`/.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) — that location is required so consumers can install via the shorthand `/plugin marketplace add kelzenberg/agentic`. Plugin bodies live here under `claude/plugins/` and the manifest's `source` paths point back into this directory.

## Layout

```
agentic/
├── .claude-plugin/
│   └── marketplace.json          ← manifest (lists plugins; required at repo root)
└── claude/
    ├── README.md                 ← you are here
    └── plugins/
        └── <plugin-name>/        ← one folder per plugin
            ├── .claude-plugin/
            │   └── plugin.json   ← required per-plugin manifest
            ├── skills/<skill-name>/SKILL.md
            ├── commands/<command>.md
            ├── agents/<agent>.md
            ├── hooks/hooks.json
            ├── references/<doc>.md
            ├── scripts/<script>
            └── .mcp.json
```

Only `.claude-plugin/plugin.json` goes inside the plugin's `.claude-plugin/` folder; all
other content dirs sit at the plugin root.

**Skills auto-discover.** Every `skills/<skill-name>/SKILL.md` under a plugin folder is picked up automatically — no per-skill entry in `plugin.json` or `marketplace.json`. To add a new skill to an existing plugin, drop a new sibling subdirectory under `skills/` and you're done. This is how [`way-of-working`](plugins/way-of-working/) grows: its [`extract-way-of-working`](plugins/way-of-working/skills/extract-way-of-working/SKILL.md) meta-skill emits each extracted skill as a sibling subdirectory under [`plugins/way-of-working/skills/`](plugins/way-of-working/skills/), and the new skill ships with the plugin on the next install/update.

## Adding a new plugin

1. **Invoke the [`onboard-to-marketplace`](plugins/marketplace-curator/skills/onboard-to-marketplace/SKILL.md)
   skill** and hand it the source folder. This is the single entry point and the only
   supported authoring path: it creates the plugin folder, scrubs PII, polishes files to
   repo standard, registers the manifest entry, and updates the root README catalog. Never
   hand-create plugin folders, manifest entries, or root README bullets.

2. **Validate** from the repo root:

   ```bash
   claude plugin validate .
   ```

3. **Run the [`check-pii`](plugins/marketplace-curator/skills/check-pii/SKILL.md) skill**
   before committing. Enable the pre-commit hook once per clone so the same scanner also
   runs on every commit:

   ```bash
   git config core.hooksPath .githooks
   ```

   The hook runs the mechanical scanner over staged changes — it does not replace the
   skill's semantic read pass. See
   [CONTRIBUTING.md § Enforcement](../CONTRIBUTING.md#enforcement) for hook, CI, and
   LICENSE details.

4. **Commit and push.**

### Appendix: what the skill produces (for reviewers)

Reference for reviewing the result of step 1 — not a procedure to follow by hand.

- The plugin folder with `claude/plugins/<name>/.claude-plugin/plugin.json`:

  ```json
  {
    "name": "<name>",
    "description": "<one-line description>"
  }
  ```

  No `version` field — Claude Code falls back to the git commit SHA, so every push is
  automatically a new version. No manual bumps.

- Plugin content under the plugin folder (`skills/`, `commands/`, `agents/`, `hooks/`,
  `references/`, `scripts/`, `.mcp.json`).

- An entry in [`/.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json),
  inserted into the `plugins` array in alphabetical order by `name`:

  ```json
  {
    "name": "<name>",
    "source": "./claude/plugins/<name>",
    "description": "<one-line description>"
  }
  ```

- A bullet for the plugin in the root [`README.md`](../README.md) catalog, in the same
  alphabetical order.

## How consumers install

Remote (after pushing to GitHub):

```bash
/plugin marketplace add kelzenberg/agentic
/plugin install <plugin>@agentic-kelzenberg
```

Local (for testing changes before pushing):

```bash
/plugin marketplace add <path-to-this-repo>
/plugin install <plugin>@agentic-kelzenberg
```

## Reference

- [Marketplace manifest schema](https://code.claude.com/docs/en/plugin-marketplaces.md)
- [Plugin structure](https://code.claude.com/docs/en/plugins.md)
- [Install commands](https://code.claude.com/docs/en/discover-plugins.md)
