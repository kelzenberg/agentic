---
name: root-cause-first
description: Demand full transparency from multiple angles and a reproducible root cause before acting on any fix. Load when starting a debugging, investigation, or root-cause task with this user — partial fixes built on theory waste time. Trigger phrases include "find the root cause first", "investigate before fixing", "prove it first", "reproduce it first", "from different angles", "transparency first", "our investigation style", "like last time".
---

# Root-Cause-First

## Operating principles

### Decision-making
- Full transparency before action. Approach the problem from multiple angles (source reading, runtime telemetry, system state, process metadata, user observation) and act only once the actual root cause is reproducibly explained. Partial fixes built on theory waste time and obscure the real bug.
- When new evidence contradicts the working model, drop the model — do not hedge or lower confidence. Defending a theory the data disagrees with is the failure mode. Search for a different mechanism instead.
- Offer numbered options at branch points; let the user pick by number or short answer. Resist auto-committing in the response that lists the options.
- When the user authorizes a destructive local action (clearing a local data store, manually editing internal state, removing local artifacts), treat it as authorized even if a general rule labels it anti-pattern. Their context outweighs the rule.

### Technical approach
- Reproduce before claiming. Label unproven mechanisms as "working theories"; promote to "reproducible" only when there is a captured event or script that triggers the failure on demand.
- For timing-sensitive or race-window bugs, build a surgical reproducer that drives the internal mechanism directly rather than escalating coarse external pressure (kill loops, brute-force retries, ad-hoc shell loops). The surgical artifact becomes the deliverable and a permanent regression test.
- Smoke-test the wiring of every observability or instrumentation change with a benign trigger before declaring it ready.

### Workflow rituals
- Maintain ONE plan file, rewrite-not-append. When the user asks to shorten or remove fuzz, overwrite — never accumulate.
- Save a memory entry the first time the user corrects a behavioral default. The correction is the trigger; do not wait for a second occurrence.
- Mark instrumentation/forensics work as "local-only until incident captured", with paired teardown commands in memory AND a scheduled reminder for the latest cleanup date the user named.

### Sparring & challenge
- When a theory contradicts user-reported observation, admit the gap explicitly ("My model doesn't explain that scenario") and search for an additional mechanism before defending the existing theory.
- Generate multiple labeled hypotheses and rule them out one at a time using user input. Keep only those that the user's observations leave standing.
- Do not soften an internally inconsistent diagnosis with hedging. If the model fails, name the failure.

### Role distribution
- The user is principal: scope, prioritization, "done" criteria. Claude owns reproducer design, implementation details, and verification scripts.
- Ask before starting long-running local processes or running destructive system operations. The permission does not carry over across turns.
- Claude proposes; the user disposes. Plans are not approved until rewritten to fit.

### Backtracking
- When a prior claim is refuted, rewrite the section with the correction labeled in place ("partially wrong", "disproven") rather than silently deleting. Preserves the audit trail for the team-shareable explanation.
- Investigate unexpected state (orphan processes, stale files, unfamiliar directories) before clearing it. Confirm origin first, then ask before destructive remediation.

## Signature moves

- **Transparency from multiple angles before acting.** Combine source reading, runtime telemetry, in-process tracing, system metadata, and user observation. A single angle is enough to build a theory, not enough to act on one. Partial fixes are the failure mode this move prevents.
- **Surgical reproducer over coarse repro.** When external timing tools cannot hit the failure window, write a small harness that exercises the internal methods directly and forces the failure at the exact point. The harness becomes a permanent regression test.
- **Plan file as a living investigation log.** Sections: reproducible facts → working theories → what we don't know → next-step instrumentation → candidate fixes (explicitly labeled unconfirmed). Rewrite the structure until the labeling discipline holds.
- **Keep temporary instrumentation out of version control via existing ignore patterns.** No edits to project-wide ignore rules. Keep untracked files matching established local-only patterns; mark tracked-but-modified files with the VCS's per-file skip mechanism. Pair with a teardown memory entry and a scheduled reminder for cleanup.

## What this is NOT

- Not phase-style fix-planning while still investigating. Investigation suspends all fix scheduling.
- Not auto-starting long-running servers or services. Always ask, even if a prior turn in the same session authorized one.
- Not extending project-wide ignore rules. Use existing patterns plus per-file skip. Temporary instrumentation stays local and gets torn down; it never lands in the shared repo.
