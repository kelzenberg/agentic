<!-- AI-drafted, 2026-08-14 -->

# PII and private-content policy

Single source of truth for what to scrub, what to keep, and how, across the `marketplace-curator` plugin. Used by [`onboard-to-marketplace`](../skills/onboard-to-marketplace/SKILL.md) at import time and by [`check-pii`](../skills/check-pii/SKILL.md) on demand. Also referenced by repo-root [`CONTRIBUTING.md`](../../../../CONTRIBUTING.md), [`AGENTS.md`](../../../../AGENTS.md), and [`CLAUDE.md`](../../../../CLAUDE.md).

Two rules govern every change to this document:

- **The scanner is the implementation.** [`../scripts/pii-scan.sh`](../scripts/pii-scan.sh) holds every detection pattern. This file describes intent, tiers, and process. Never paste a pattern, a `grep` pipeline, or a reduced "quick check" into any skill, doc, or workflow — invoke the script.
- **The scanner is not the whole policy.** Patterns catch shapes (emails, paths, hosts, secrets). Names, employers, customers, and anecdotes have no shape; only the semantic read pass in `check-pii` catches those. A green scan is a precondition for publishing, never a verdict on its own.

## The scanner

```
claude/plugins/marketplace-curator/scripts/pii-scan.sh [--scope <path>] [--staged] [--auto-only] [--self-test]
```

| Flag | Effect |
|---|---|
| *(none)* | Scans the whole tree: `git ls-files --cached --others --exclude-standard`, so untracked-but-not-ignored files are included. |
| `--scope <path>` | Restricts the scan to a path inside the repo. Disables the git-history pass. |
| `--staged` | Scans the staged file set (`git diff --cached --diff-filter=ACMR`) instead. Used by the pre-commit hook. Reads working-tree content, so a partially staged file is judged by what is on disk. A staged set that is non-empty but contains no readable content — a deletion-only commit — emits `INFO staged-content none` and exits 0. A genuinely empty index (`git commit --allow-empty`) is still exit 2: a gate with nothing to verify fails closed. |
| `--auto-only` | Emits HIT records only; the CAND (borderline) tier is skipped. A scan run this way can never support a public-safe YES. |
| `--self-test` | Runs the built-in regression suite against synthetic fixtures in a temporary directory, prints `PASS` / `FAIL` per case, and exits 2 if any case fails. Writes nothing into the repo. |

Exit codes: `0` = no HIT records, `1` = at least one HIT, `2` = scan error (empty file list, `grep` failure, missing dependency, invalid allowlist, unknown argument). Anything other than 0 or 1 means the scan did not happen — never read it as "clean".

Dependencies: `bash`, `git`, `grep`, `file`, `awk`, `tr`, `sort`, `jq`.

### Output protocol

One record per line on stdout, TAB-separated:

```
HIT         <file>  <line>  <category>  <fragment>
CAND        <file>  <line>  <category>  <fragment>
SUPPRESSED  <file>  <line>  <category>  <fragment>
SCANNED     <file>
MANUAL      <file>  -       <binary|unreadable>  <mime-type or reason>
INFO        <key>   <value>
SUMMARY     files=<n> hits=<n> cand=<n> suppressed=<n> manual=<n> mode=<full|auto-only> scope=<path|full-tree|staged:...>
```

`SCANNED` is emitted once per text file the scanner actually read, before any finding for it. It exists so the semantic pass in `check-pii` can enumerate its read set: findings alone would name only the files that already failed, and the whole point of reading is to reach the files no pattern flagged. The count of `SCANNED` records equals `files=` in the `SUMMARY`.

`<line>` is `-` where the finding has no line: filename matches and git-history matches (whose `<file>` reads `git-history` or `git-refs`).

`INFO` keys: `allowlist-tier2` (resolved tier-2 values, or why there are none), `untracked-count` (untracked files pulled into the scan), `license-copyright` (see below), `git-meta` (why the history pass was skipped or unavailable), `missing-in-worktree` (enumerated files absent on disk), `staged-content` (`none` when a staged set holds no readable content).

`files=` counts text files actually content-scanned. Binaries are never counted as scanned — they are reported `MANUAL` and need human eyes.

A run that scanned nothing is never clean: when `files=0` while `manual>0`, the scanner emits `HIT scan-scope - unscannable …` and exits 1, so a commit or a CI job made only of binaries cannot pass a gate that never read anything.

### Detection tiers

| Category | Tier | What it flags |
|---|---|---|
| `email` | HIT | Address-shaped tokens. Reserved example domains and an allowlisted handle at `users.noreply.github.com` are dropped. |
| `path` | HIT | Home and profile paths, matched to the end of the path, not just the prefix. |
| `host` | HIT | URLs and bare host tokens on the known-private-host list, matched case-insensitively, plus internal host labels in host position. |
| `unscannable` | HIT | The scope produced no scannable text file while reporting `MANUAL` ones. Pseudo-file `scan-scope`. |
| `secret` | HIT | API keys, personal access tokens, session tokens, JWTs, private-key headers. |
| `ip-private` | HIT | Valid IPv4 in RFC 1918, loopback, or link-local space — internal infrastructure. |
| `ip` | CAND | Valid public IPv4 and IPv6 addresses. Noisy by nature (version strings look alike), so a human judges. |
| `phone` | HIT | International `+CC` numbers, 8–15 digits, in E.164-ish shape: a 1–3 digit country code followed by a separator. The separator is required so that `+`-prefixed ISO dates and numeric ids in diff snippets are not auto-fails. |
| `iban` | HIT | Bank account numbers. |
| `ticket` | CAND | Project and ticket codes. Public technical vocabulary is filtered out. |
| `filename` | HIT | The file path itself carries an address, a private host, or a home path. |
| `filename` (`name`) | CAND | The file path carries a person-name bigram (`First-Last`). Borderline, not an auto-fail: a filename has no line to mark, so a HIT here would block the hook and CI until the file were renamed. |
| `git-meta` | HIT | Commit author or committer address that is neither allowlisted nor a GitHub machine identity; branch and tag names carrying an address or private host. Full-tree runs only. GitHub's own identities are exempt — the `users.noreply.github.com` domain (contributor no-reply addresses and `<app>[bot]` committers) and the `noreply` address at `github.com` that authors the synthetic merge commit on `refs/pull/N/merge`. Without that exemption every `pull_request` CI run would fail on a finding no contributor can fix. |

Home and profile path forms covered: `/Users/`, `/home/`, `C:\Users\`, the dash-encoded project-directory form `-Users-` that Claude Code itself produces, tilde paths into `Developer`, `Documents`, `Desktop`, `Downloads`, `Projects`, macOS temporary paths under `/var/folders/`, and the Windows profile variable `%USERPROFILE%`. <!-- pii-ok: pattern-doc -->

### Known private hosts

A URL whose host is, or sits under, one of these is company-private until proven otherwise. `*.` covers the apex and every subdomain.

- Docs and boards: `*.notion.so`, `*.notion.site`, `*.linear.app`, `*.atlassian.net`, `*.asana.com`, `*.monday.com`, `*.airtable.com`.
- Chat and meetings: `*.slack.com`, `*.teams.microsoft.com`, `*.zoom.us`, `*.calendly.com`, `*.t.me`.
- Files and office suites: `*.sharepoint.com`, `*.onedrive.live.com`, `*.office.com`, `*.docs.google.com`, `*.drive.google.com`, `*.dropbox.com`.
- Design and whiteboards: `*.figma.com`, `*.miro.com`, `*.lucid.app`.
- Code hosting: `*.gitlab.com`, `*.bitbucket.org`, `*.gist.github.com`. Public `github.com` repository and docs URLs are allowed; gists are per-person pastes and stay private.
- Cloud consoles: `*.aws.amazon.com`, `*.azure.com` (covers the DevOps subdomain), `*.azurewebsites.net`, `*.googleapis.com`.
- Support, CRM, observability: `*.zendesk.com`, `*.salesforce.com`, `*.hubspot.com`, `*.posthog.com`, `*.sentry.io`, `*.grafana.com`, `*.grafana.net`, `*.datadoghq.com`, `*.datadoghq.eu`, `*.pagerduty.com`, `*.opsgenie.com`.
- Internal infrastructure: any host with an `internal`, `intranet`, `corp`, or `vpn` label, or ending in `.internal` / `.intranet` / `.corp`. These are evaluated against a parsed host, and only when something marks the token as a host: a URL scheme, or a final label that can plausibly be a TLD. Without that anchor the token is left alone, so `docs/internal.md`, the Java identifier `corp.acme.Service`, and the package path `com.example.internal.util` are not findings. A bare word "internal" in prose never was one. The trade is deliberate: an internal host written without a scheme and with an unusual final label is left to the semantic pass.

If the user states that a URL on one of these hosts is genuinely public documentation, keep it — with a `pii-ok` marker recording that decision. To cover a host the list misses, add it to the scanner's list, never to a skill.

### Suppression rules

Applied in this order to every candidate fragment:

1. **Fragment-scoped placeholder filter.** A fragment is dropped only when the fragment *itself* is entirely a placeholder — `<placeholder>` form, a `*.`-glob over a whole listed domain, or a reserved example host (`example.com`, `example.org`, `example.net`, `*.example`, `*.invalid`, `*.test`, `localhost`). A placeholder elsewhere on the line never suppresses anything: a real address next to `<email>` in the same sentence is still a HIT. A glob over a *subdomain* still names a tenant, so it stays a HIT.
2. **Line marker.** A `pii-ok` marker on the same source line turns HIT into `SUPPRESSED`. Suppressed lines stay in the report and in the summary count, so the blind spot is always visible. This is the only mechanism for exempting documentation of the patterns themselves — there is no file-level exclusion, for any file, ever.

   The marker must sit **in comment position**, in one of exactly two forms: `<!-- pii-ok: <reason> -->` (Markdown and HTML) or `# pii-ok: <reason>` (shell, YAML, and anything else with `#` comments). A bare `pii-ok:` inside a string, a code literal, or a data field does **not** suppress anything — otherwise any value carrying that text would silence every finding on its line, which is a bypass, not a policy.

   In `.json` and `.jsonl` files the marker is **refused outright** and the record stays a HIT. JSON has no comment syntax, so a marker there can only be data. Scrub the value or move the example into a documented Markdown file.
3. **Allowlist**, applied to the identifying component only, never as substring containment. Every category is routed through this rule; what counts as the identifying component depends on the category:

   | Category | Identifying component |
   |---|---|
   | `email` | the domain, plus the local part for `users.noreply.github.com` |
   | `host`, `filename` (host) | the registrable host |
   | `filename` (`name`) | either half of the bigram, or the halves joined with a space |
   | `path`, `filename` (path) | the user-directory component (`/Users/<here>/…`, `C:\Users\<here>\…`, `-Users-<here>-…`) | <!-- pii-ok: pattern-doc -->
   | `secret`, `ip`, `ip-private`, `phone`, `iban`, `ticket` | none — an allowlist names people and organizations, so no literal can clear a credential or an address |

   `agentic@some-employer.example` is a HIT even though `agentic` is allowlisted: the domain is the component, and it is not on the list.

   One caveat on `path`: allowlisting the user component stops the auto-fail, it does not make the path publishable. A home path still names a local checkout layout, and its tail can still name an engagement, so the auto-scrub rule below applies regardless. A green scan is not permission to keep it.
4. **Public-URL allowance.** `github.com` (gists excluded), `claude.com`, and `anthropic.com` URLs are public by definition.

Example of a marked line — this bullet is itself marked, which is why the scanner reports it as `SUPPRESSED` instead of a `path` HIT: profile variable `%USERPROFILE%` <!-- pii-ok: pattern-doc -->

Marker discipline: one reason per marker, and the reason names the category (`pattern-doc`, `public-docs-url`, `fixture`). A marker is a decision on the record, not a mute button.

## Allowlist (two tiers)

### Tier 1 — permanent attribution literals (always keep)

The repository LICENSE requires preserving original authorship. These literals are permitted anywhere in the repo and must NOT be removed by any forker:

- `kelzenberg` (original repo author)
- `agentic-kelzenberg` (original marketplace name)
- `agentic` (repo short-name)
- `Anthropic`, `Claude`, `Claude Code`
- Reserved example domains, in documentation examples only.

### Tier 2 — current identity (read from the manifest at runtime)

Additionally permitted: the live `owner.name` and `name` fields in [`.claude-plugin/marketplace.json`](../../../../.claude-plugin/marketplace.json). For the original repo these equal tier 1; a fork adds the fork owner's handle and marketplace name.

Tier-2 values are **validated before they are trusted**, because whatever sits in that field is otherwise granted blanket clearance. Each value must match `^[a-z0-9][a-z0-9 _-]{1,38}$` case-insensitively and must not be address-shaped. A value that fails — a legal name, an email, anything with punctuation beyond space, underscore, and hyphen — aborts the scan with exit 2 rather than silently widening the allowlist. Forkers: use a handle in these fields, never a legal name.

## Auto-scrub (always replace)

| Match | Replacement |
|---|---|
| Email address | `<email>` — in JSON, delete the field with `jq 'del(...)'` rather than hand-editing lines |
| Home or profile path (whole path, not just the prefix) | `<path-to-repo>` |
| Other absolute local path | `<path-placeholder>` |
| URL on a known private host | `<internal-url>` |
| Internal hostname | `<host>` |
| API key, token, private key | `<secret>` — and rotate it; a scrub does not un-leak a live credential |
| IP address | `<ip>` |
| Phone number | `<phone>` |
| Bank account number | `<iban>` |
| Ticket or project code | `<ticket-id>` |
| Personal account handle | `<handle>` |
| Person name | `<name>` |
| Company name | `<company>` |
| Customer or vendor identifier | `<customer>` |

Replace the **entire** matched fragment. Scrubbing a path prefix and leaving `/Developer/private-client-work` behind keeps the part that identifies the engagement.

## Borderline — ask the user (keep or scrub, per item)

Nothing in this tier is grep-able. It is found by reading the files, which is why `check-pii` runs a mandatory semantic pass and why `--auto-only` can never produce a public-safe YES. Present findings as one batched list with a keep/scrub choice each:

- Real names (first plus last) outside the allowlist.
- Employer, customer, and vendor names.
- Internal project codenames, private repository names, and channel names.
- Internal hostnames not on the known-private-host list, including custom subdomains and `.local` / `.lan` machine names — macOS names a machine after its owner by default.
- Anecdotes, retro notes, and verbatim quotes that identify who wrote a file.
- Every `CAND` record: public IPs, IPv6 addresses, and ticket codes are judged, not auto-scrubbed.

### Correlation signals

Individually weak, jointly identifying. Surface each for a keep/scrub decision; do not auto-scrub.

- Non-UTC commit timezone offsets, and commit-hour patterns that pin a working day.
- Country-specific SaaS vendors, national TLDs, and currency symbols in examples.
- Locale-specific date and number formats where the repo standard is ISO.
- A single natural language across all examples, when it is not the repo's documented language.
- Ticket-ID prefixes and project codenames, which cross-reference against public job posts and talks.

## Manual review — binaries

Binary files are **unscannable, not clean**. `grep` cannot read them, so the scanner reports every one as a `MANUAL` record and never counts it as scanned. Each needs an explicit human decision before publishing, because image EXIF (owner name, GPS, camera serial), PDF and Office document metadata, and `.DS_Store` (an index of sibling filenames, including deleted ones) all carry PII that no pattern will ever see. Prefer not to commit binaries at all; a screenshot of private content is forbidden outright.

## LICENSE

`LICENSE` and `LICENSE.*` are excluded from pattern matching — the copyright line is attribution, not a leak — but they are **not** silently skipped. The scanner emits `INFO license-copyright <line>` on every run, and `check-pii` echoes it for explicit confirmation. No skill ever edits a LICENSE file.

## Action on hit

`check-pii` and `onboard-to-marketplace` MUST NOT silently auto-edit user-authored content. The flow is:

1. Run the scanner. Treat exit 2 as a failed scan, never as a clean result.
2. Classify: HIT is auto-scrub, CAND and everything from the semantic pass is borderline.
3. Compute the replacement from the placeholder vocabulary above, covering the whole fragment.
4. Show a unified diff per file.
5. HIT items default to apply; borderline items default to ask, one decision each.
6. After editing JSON, validate it (`jq -e .`) before claiming anything is done.
7. Re-run the scanner and require zero HIT records. A scrub that was never re-verified is not a scrub.

## Enforcement

- Local: [`.githooks/pre-commit`](../../../../.githooks/pre-commit) runs the scanner over the staged set and blocks the commit on exit 1 or 2. Enable it once per clone with `git config core.hooksPath .githooks`.
- CI: [`.github/workflows/pii-scan.yml`](../../../../.github/workflows/pii-scan.yml) runs `--self-test` and a full-tree scan on every push and pull request, on a full-depth checkout so the git-history pass has refs to read.
- On demand: the `check-pii` skill, which adds the semantic pass the automation cannot do.

None of these replace the others. The hook covers what is being committed, CI covers what landed, and the skill covers what no pattern can express.
