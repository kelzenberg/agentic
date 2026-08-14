---
name: guided-ux-walkthrough
description: Use when the user asks for a live, watched review of a change in a headed browser (Playwright MCP or similar) — presenting work for their judgment on screen rather than merging on green tests. Trigger phrases include "walk me through your changes", "preview via the browser, I'll watch", "visual QA", "guided walkthrough", "present the changes step-by-step", "demo the change".
---

# Guided UX Walkthrough

A staged live review: Claude drives a headed browser the user watches, presents one change at a time for their judgment, and treats their remarks as review findings to collect — not tasks to start on. Works for any change that can be shown in a browser.

## The step loop

The core contract, per step, in one turn:

1. **Prepare** — drive the browser into the state (silently; don't narrate plumbing like scrolling or clicking through menus).
2. **Call attention** — tell the user to look now.
3. **Present** — as bullets: **what** changed, **where** on screen, **what to look for and when** (critical for effects lasting under a second).
4. **Preview** — one line on what the next step will show.
5. **Stop.** Wait for the user's remarks or "next". Never batch steps — the user watches a separate window and misses everything otherwise.

Give a numbered step plan (titles only) up front; keep the detailed where-to-look pointers inside each step, never front-loaded.

## Operating principles

### Decision-making
- The user is the sole judge of what's on screen. End a step with explicitly labeled judgment questions; a bare "next" answers the pending question as approval — record it as a decision, not an open item.
- Present deliberately-unchanged paths too, framed as "this step asks you to judge whether that decision holds". The review covers decisions, not just diffs.
- When a remark's fix has two defensible interpretations (e.g. which edge to align to), put the question in the fix plan with measurements — never guess.

### Technical approach
- Before judging anything, verify the browser serves the code under review: correct branch/checkout on the port, stack healthy. A demo of the wrong build is worse than no demo.
- Seed state engineered for visibility: pick data scale that makes the effect unmissable (a page that overflows several screens makes a scroll-to-top obvious; three items don't). If a state-seeding skill or script is available, use it.
- Instrument what screenshots can't catch: arm observers *before* the triggering action, sample positions during animations, read short-lived toasts from the DOM, freeze a styled clone of expired elements for inspection — and remove injected artifacts afterwards.
- Evidence is before/after tables of measured facts (scroll offset, heights, counts, pixel positions), not narrative claims.

### Workflow rituals
- Do not lose any remarks: write each one to a numbered on-disk file at capture time; annotate with root-cause and coupling notes (shared string, same element as remark N) without acting; keep a running count in every recap.
- Close the pass with a structured recap: verified-live table, remark list with count, environment residue (what data was mutated and how to reset it), states not reachable with this data named explicitly, open judgment items.
- After the batch fix, run a re-verification walkthrough of every remark under the same protocol; reorder steps opportunistically when the current screen already shows a later one.

### Sparring & challenge
- Answer user questions mid-pass immediately, with evidence (provenance from history, measurements), then return to the step.
- Surface pre-existing contradictions adjacent to the change for judgment, even when out of scope.
- Correct your own earlier claims visibly when evidence overturns them; never let a wrong assertion stand because the moment passed.

### Role distribution
- Claude drives the browser and waits; the user only watches and judges. Offer the drive-mode choice once if unclear.
- UX language, not code: describe what a user sees change, not the diff. Implementation detail belongs in the PR/MR description — narrating it here is "reviewing my own diff at you instead of showing you a product".
- The user's window is theirs: if they resize it, match the viewport to the measured window and re-measure each step.
- Prefix anything needing the user's input with a prominent marker (e.g. 🔴) and **hold** — asking a question and driving on in the same turn is jumping ahead.
- Environment recovery is Claude's job (re-authenticate on logout, restore exact state from the URL, warn about window flicker); restarting the user's dev servers is not.

### Backtracking
- "I didn't see anything" means fix visibility first (raise/resize the window, confirm the user sees it), reset to a clean start, and restart the step sequence — never argue the demo happened.
- When a fix breaks on a state the user built live: reproduce on their exact state, root-cause it, fix, prove the covering test discriminates (red on the old behavior), then re-verify on that same state before continuing.

## Signature moves

- **The step loop, verbatim.** Its violation — blowing through every step in one turn — is the failure this skill exists to prevent.
- **Remark file on disk from the first remark**, numbered, annotated at capture, never acted on mid-pass.
- **Observer-before-action instrumentation** plus frozen clones for UI that expires faster than a screenshot round-trip.
- **Fixture chosen for visibility**, and a pre-judgment check that the served code is the code under review.

## What this is NOT

- Not a code review: no diff narration, no framework-internals explanations in the walkthrough. If a sentence only makes sense to someone who read the diff, it belongs in the PR/MR.
- Not a fix session: remarks are collected, not fixed, until the pass ends and the user asks for the plan. The one exception: a fix that breaks during re-verification and the user says fix it now.
- Not autonomous verification: driving solo and reporting one consolidated pass/fail table at the end is fine when the user hasn't asked to watch — this skill is the joint mode. Either way, no commit, push, or PR/MR action without explicit instruction.
