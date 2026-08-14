---
name: check-pii
description: Use to verify the repo (or a subtree) contains no PII or links to personal / company-private content before commit, push, or PR. Trigger phrases include "check pii", "scan for personal info", "audit for private content", "is this public-safe", "is this safe to push", "/check-pii", "before I commit", "before I push", or any time the user prepares to make the repo or a change public. Runs the canonical scanner `../../scripts/pii-scan.sh`, reads the policy from `../../references/pii-policy.md`, and reads the allowlist additionally from `.claude-plugin/marketplace.json`.
---

# Check PII

On-demand scan for personal identifying information and links to personal / company-private content across the repo (or a chosen subtree). Used as the final sanity check before commit / push / PR.

Two controls, both required for a clean verdict:

1. **Mechanical pass** — [`../../scripts/pii-scan.sh`](../../scripts/pii-scan.sh) is the single source of truth for every pattern, tier, and suppression rule. Never re-type or reduce its patterns here.
2. **Semantic pass** — a mandatory read of the scanned files by the model. Names, employers, customers, codenames, and anecdotes are not grep-able; reading is the only control that reaches them. A verdict without it is unsupported.

This skill does NOT auto-edit. It reports findings and proposes diffs; the user (or the invoking agent) decides what to apply.

Policy, placeholder vocabulary, and tier definitions: [`../../references/pii-policy.md`](../../references/pii-policy.md).

## Inputs (gather once, then proceed)

| Input | Required | Notes |
|---|---|---|
| Scope | no | Default = whole tree (tracked + untracked-not-ignored). User may pass a subpath (e.g., `claude/plugins/quick-capture/`) → forwarded as `--scope <path>`. |
| `--auto-only` | no | Default = off. User says "auto only" → skip the borderline tier entirely (scanner omits `CAND`, skill skips §4). A `YES` verdict is then impossible; see §5. |
| `--staged` | no | Pre-commit-hook mode: scan the staged file set instead of the tree. Verdict is scope-qualified, never repo-wide. |

## Workflow

### 0. Preflight

- Assert a git repository: `git rev-parse --show-toplevel`. Run every later step from that root.
- Assert each dependency with `command -v` — the scanner's own list, so the skill cannot pass a preflight the script then fails: `git`, `grep`, `file`, `awk`, `tr`, `sort`, `jq`. On a miss, refuse and **name the missing dependency** (never continue degraded — a missing tool must not read as a clean scan).
- Resolve the scanner path and assert it exists and is executable (`-x`):
  - working in this repo → `claude/plugins/marketplace-curator/scripts/pii-scan.sh` (i.e. `../../scripts/pii-scan.sh` relative to this skill);
  - plugin installed elsewhere → `"${CLAUDE_PLUGIN_ROOT}/scripts/pii-scan.sh"`.
- Missing or non-executable script → refuse (§7). Do not fall back to an inline grep.

### 1. Resolve scope

- No scope given → full tree. The scanner enumerates `git ls-files -z --cached --others --exclude-standard`, so **untracked-but-not-ignored files are included** — the set that the next `git add -A` would sweep in.
- Scope given → pass it verbatim as `--scope <path>`. Refuse if the path does not exist or resolves to zero files (likely a typo; the scanner exits 2).
- Report the untracked count explicitly from the scanner's `INFO` record for untracked files (`INFO<TAB>untracked-count<TAB><n>`); if that record is absent, derive it with `git status --porcelain --untracked-files=all` limited to scope.
- State in the report what is **not** covered: files ignored by `.gitignore`, and — on a scoped or `--staged` run — the rest of the tree.
- `--staged` over a staged set with no readable content (a deletion-only commit) yields `INFO<TAB>staged-content<TAB>none`, `files=0`, and exit 0. Report it as "nothing to scan", never as a clean verdict — `YES` still requires `files>0` (§5).
- `LICENSE` / `LICENSE.*` are not pattern-matched; the scanner instead emits `INFO<TAB>license-copyright<TAB><line>` for explicit confirmation (§5). LICENSE is never edited.

### 2. Load and validate the allowlist

- Tier 1 (fixed literals): `kelzenberg`, `agentic-kelzenberg`, `agentic`, `Anthropic`, `Claude`, `Claude Code`.
- Tier 2 (repo-derived):

  ```bash
  jq -r '.owner.name, .name' .claude-plugin/marketplace.json
  ```

- **Validate before trusting** — an allowlist entry is a blanket suppression, so a real name placed there would blind the scan:
  - each value must match `^[a-z0-9][a-z0-9 _-]{1,38}$` case-insensitively (handle shape);
  - no value may match the email pattern.
- Validation failure → abort with the offending field and value; do not scan, do not print a verdict (§7). The scanner enforces the same rule and exits 2, so the two cannot drift apart silently.
- Allowlisting applies to the **identifying component** — an email's local part or domain, a URL's registrable host, a whole borderline token. Substring containment is never sufficient: an address of the shape `agentic@<private-domain>` stays a hit despite containing `agentic`.

### 3. Run the scanner

From the repo root, with the path resolved in §0:

```bash
claude/plugins/marketplace-curator/scripts/pii-scan.sh [--scope <path>] [--staged] [--auto-only]
# installed plugin:
"${CLAUDE_PLUGIN_ROOT}/scripts/pii-scan.sh" [--scope <path>] [--staged] [--auto-only]
```

Output is TAB-separated, one record per line:

| Record | Meaning | Handling |
|---|---|---|
| `HIT<TAB>file<TAB>line<TAB>category<TAB>fragment` | tier-1 auto-fail | blocks a `YES` verdict until fixed |
| `CAND<TAB>file<TAB>line<TAB>category<TAB>fragment` | mechanical borderline candidate | must be judged in §4 |
| `SUPPRESSED<TAB>file<TAB>line<TAB>category<TAB>fragment` | dropped by a `pii-ok` comment marker on that line | count and report; spot-check that each marker is still justified |
| `SCANNED<TAB>file` | one per text file actually content-scanned | this is the §4 read set |
| `MANUAL<TAB>file<TAB>-<TAB>binary\|unreadable<TAB>mime or reason` | not scanned: a binary, or a path the scanner could not read | needs explicit human clearance either way |
| `INFO<TAB>key<TAB>value` | license copyright, untracked count, skipped passes | echo in §5 |
| `SUMMARY<TAB>files=… hits=… cand=… suppressed=… manual=… mode=… scope=…` | run totals | anchor the §5 summary to these numbers |

Exit codes: `0` = no `HIT` (findings may still exist as `CAND`/`MANUAL`), `1` = at least one `HIT`, `2` = scan error. Exit 1 is a normal finding outcome, not a tool failure — continue to §4. Exit 2 → refuse (§7); never print a verdict from an errored scan.

### 4. Semantic read pass (MANDATORY)

Skip only under `--auto-only`, which forfeits any `YES` verdict.

Read the files — this is the control, not a formality:

- The read set is the scanner's `SCANNED` records — one per text file it content-scanned. Collect them, and check that their count equals `files=` in `SUMMARY`; a mismatch means the output was truncated, so stop rather than read a partial set. Never substitute "the files that produced findings" for this set: that inverts the pass, since a clean-looking file is exactly where an unpatterned name hides.
- Read **every** file in that set. Files ≤400 lines: read in full. Larger files: read all headings plus a window around every `HIT`/`CAND` line, and the first and last 100 lines.
- Judge **every** `CAND` line explicitly — keep, scrub, or ask. An unjudged `CAND` blocks `YES`.
- Hunt the categories no pattern can reach:
  - real names (first + last together), usernames tied to a real person;
  - employer, company, customer, vendor, or agency names;
  - internal project codenames, private repository names, ticket-ID prefixes, channel names;
  - anecdotes, retro notes, meeting recaps, or verbatim personal quotes that identify who wrote a file;
  - correlation signals per the policy's borderline tier: country-specific vendors, national TLDs, region-tied currency, locale date formats, non-UTC timestamps.
- Check **paths as well as contents** — a directory or file named after an employer, customer, or person leaks in the tree view even when the body is clean.
- Track the count of files actually read; §5 prints it. Never claim a file was read that was only listed.

### 5. Report

One table sorted by file:

```
file                              | line | category | fragment                | tier
----------------------------------|------|----------|-------------------------|-----------
claude/plugins/foo/SKILL.md       |   12 | email    | <the-real-fragment>     | auto-fail
claude/plugins/foo/SKILL.md       |   34 | path     | <the-real-fragment>     | auto-fail
README.md                         |   42 | host     | <the-real-fragment>     | auto-fail
claude/plugins/bar/SKILL.md       |   88 | ticket   | <the-real-fragment>     | borderline
claude/plugins/bar/refs/logo.png  |    - | binary   | image/png               | manual
```

The `fragment` column carries the real matched text in an actual report; the stand-ins above exist only so this documentation file does not self-match.

Three `<file>` values are pseudo-files, not paths — report them as such, never as files someone can open:

- `git-history` and `git-refs` (category `git-meta`, line `-`) — a commit identity or a branch / tag name. These are history findings; rewriting history, not editing a file, is the fix.
- `scan-scope` (category `unscannable`, line `-`) — the scope produced zero scannable text files while reporting `MANUAL` ones. Nothing was verified, so this is an auto-fail, not a clean run.

Then the summary. Print the LICENSE line on every run:

```
Scope: <full tree (tracked + untracked-not-ignored) | <path> | staged set> — <n> files
Untracked files included: <n>. Not covered: .gitignore-ignored files<, plus <m> files outside the scope>.
Read in semantic pass: <n> files (<n> full, <n> skimmed).
Findings: <h> auto-fail, <c> borderline, <s> suppressed by pii-ok marker, <b> binaries needing manual review.
LICENSE copyright: <the copyright line> — confirm intentional
<verdict line>
```

Verdict rules — the phrasing is load-bearing, do not improvise:

| Run | Verdict line |
|---|---|
| Full tree, all clear | `Repo public-safe: YES (syntactic pass + semantic pass, <n> files read)` |
| Full tree, any auto-fail / unjudged borderline / uncleared binary | `Repo public-safe: NO` |
| Scoped or `--staged`, all clear | `Scope public-safe: YES (syntactic pass + semantic pass, <n> files read)` plus `Not scanned: <m> other files — re-run without a scope before push.` |
| Scoped or `--staged`, any finding | `Scope public-safe: NO` (+ the same not-scanned line) |
| `--auto-only`, no auto-fail | `<Repo|Scope> public-safe: UNKNOWN (borderline tier not evaluated — re-run without --auto-only before publishing)` |
| `--auto-only`, any auto-fail | `<Repo|Scope> public-safe: NO` |
| Scanner exit 2 | no verdict — report the scan error and refuse (§7) |

Hard constraints:

- `Repo public-safe:` is reserved for full-tree runs. A scoped run never prints it, in any wording.
- `YES` is forbidden under `--auto-only`, and forbidden when the semantic pass did not run.
- `YES` requires `hits=0`, every `CAND` judged and cleared, and every `MANUAL` binary explicitly cleared by the user.
- `YES` requires `files>0` in `SUMMARY` — an empty scan is an error, not a pass.

### 6. Fix flow (only on explicit request)

Default is report-only. Apply nothing unless the user asks for fixes.

- Replace the **entire matched fragment** with its placeholder from the [`pii-policy.md`](../../references/pii-policy.md) vocabulary — for a path that means the whole path including every directory segment, not just the home-directory prefix. A truncated replacement leaves the employer or client name behind while the re-scan turns green.
- Borderline items: batch them into one prompt, ask keep / scrub / placeholder per item.
- Show a unified diff per file. Apply only on confirmation.
- **JSON files: never hand-delete a line** (trailing-comma hazard). Remove fields structurally, e.g. `jq 'del(.author.email, .owner.email)' file.json` written back with `--indent 2`.
- After any JSON edit, validate before claiming anything:

  ```bash
  git ls-files -z '*.json' | xargs -0 -n1 jq -e . >/dev/null
  ```

  A parse failure aborts the done-claim — say which file is broken and stop.
- Never touch `LICENSE`; the copyright line is confirmed by the user, not edited by this skill.
- Re-run §3 → §5 after applying, and repeat until zero `HIT` lines remain. Only then may a verdict be printed.
- Stop there: do **not** run `git add`, `git commit`, or `git push`. The user's commit flow stays in control.

### 7. Refuse if

- Run outside a git repository (no `.git/` upward).
- A required dependency is missing — `git`, `grep`, `file`, `awk`, `tr`, `sort`, or `jq` (name it).
- `claude/plugins/marketplace-curator/scripts/pii-scan.sh` (or `${CLAUDE_PLUGIN_ROOT}/scripts/pii-scan.sh`) is missing or not executable.
- Allowlist validation fails: `owner.name` or `name` is not handle-shaped, or looks like an email address.
- `.claude-plugin/marketplace.json` is missing or unparseable (the allowlist source is gone — fix that first).
- `../../references/pii-policy.md` is missing (the policy source is gone — fix that first).
- Scope path does not exist or resolves to zero files.
- The scanner exits 2 (scan error) — report the error verbatim, print no verdict.

## Anti-patterns

- Printing any `public-safe: YES` without the §4 semantic read pass, or under `--auto-only`.
- Printing `Repo public-safe:` for a scoped or `--staged` run.
- Treating an empty scanner output as clean without checking the exit code and `files=` count.
- Inlining, re-typing, or reducing the scan patterns anywhere — `pii-scan.sh` is the single scanner; invoke it.
- Embedding patterns or allowlists in this SKILL.md instead of reading them from the script and `pii-policy.md` (drift).
- Silently auto-editing files without showing a diff.
- Replacing only part of a matched fragment (leaves the private path tail or domain in place).
- Hand-editing JSON to remove a field, or declaring done without re-validating every JSON file.
- Skipping the allowlist validation, or treating substring containment as an allowlist match.
- Reporting binaries as scanned — they are `MANUAL`, unread until a human clears them.
- Treating borderline findings as auto-fail (defeats the human-in-the-loop intent).
- Editing `LICENSE`.
- Adding `git add` / `git commit` calls — the repo's commit flow is owned by the user (see root `CONTRIBUTING.md`).
