---
name: extract-way-of-working
description: At the end of a productive Claude session — or against a transcript of a past one — analyze the conversation and emit a reusable "way-of-working" skill that captures the decision-making patterns, technical approach, workflow rituals, sparring-partner methods, role distribution between Claude and the user, and backtracking habits that made the collaboration effective. Trigger when the user says things like "extract our way of working", "save how we just worked", "capture this collaboration style", "turn this conversation into a reusable pattern", "I want to repeat this", "what worked about this session", references a past transcript they want distilled, or asks to preserve, replicate, or codify an interaction style.
---

# Extract Way of Working

Analyze a Claude ↔ user conversation that the user found effective, and emit a **reusable skill** that captures the transferable patterns of how they worked together. The output is consumed by future sessions to mirror the same collaboration mode.

The whole exercise stands or falls on one rule: **every principle must be traceable to a specific turn in the source conversation.** Generic prompt-engineering advice is failure. Named frameworks are analytical lenses, not labels to drop.

---

## Step 1 — Locate the source conversation

The user supplies one of two modes:

- **(A) A path to a transcript file** — `.jsonl`, `.md`, or any exported chat log. Use the Read tool. For long transcripts, read in chunks and keep running notes in a scratch file in the outputs directory.
- **(B) Nothing** — analyze the *current session up to this point*. Use `mcp__session_info__list_sessions` then `mcp__session_info__read_transcript` to pull the transcript. If those tools are unavailable, work from the context window.

If the mode is ambiguous, ask once. Then proceed without further confirmation.

Record the source (path or session ID + ISO date) — it goes in the final skill.

---

## Step 2 — Analyze through six lenses

For each lens, find concrete *evidenced* patterns. Use the named frameworks as analytical lenses — apply them, do not namedrop them. Keep turn-references in your scratch notes; they are the audit trail for the Step 5 presentation and the Step 7 self-verify.

The six lenses are deliberately chosen: they cover the dimensions where collaboration norms actually live, rather than surface tone.

### 1. Decision-making patterns — how were choices framed and resolved?

Frameworks: RAPID/DACI roles · Cynefin (was the approach matched to the domain's complexity?) · one-way vs. two-way doors · satisficing vs. maximising.

Probes: When did the user ask vs. decide? When did Claude propose options vs. pick? How were trade-offs surfaced? Were reversible and irreversible choices treated differently?

### 2. Technical approach — how was the work executed?

Frameworks: Driver/Navigator pair programming · TDD red-green-refactor · tracer-bullet development · YAGNI · "make it work / make it right / make it fast."

Probes: Tooling sequence, verification habits, iteration size, when stubs vs. real implementations were used, where shortcuts were taken or rejected and why.

### 3. Workflow rituals — what recurring structures shaped the session?

Frameworks: Definition of Done · WIP limits · checkpoint cadence · GTD's capture/clarify/organize/reflect/engage.

Probes: Task lists, planning passes, mid-flight summaries, explicit hand-offs, sign-offs, how "done" was determined.

### 4. Sparring-partner methods — how were disagreement and challenge handled?

Frameworks: Socratic questioning · steelmanning · red-team/blue-team · Rapoport's rules ("state the other side so well they'd endorse it") · pre-mortems · devil's advocacy.

Probes: Where did Claude push back? Where did the user push back? How were alternatives stress-tested? When were unstated assumptions named? How was disagreement resolved without one side capitulating?

### 5. Role distribution (Claude vs. user) — who held which responsibility?

Frameworks: Oncken's "monkey on the back" (who owns the next action) · Marquet's Ladder of Leadership ("I intend to…") · principal-agent delegation levels (1 = ask permission … 7 = act and review).

Probes: Who proposed, who decided, who executed, who verified? Where did authority shift, and what triggered the shift? Was the user functioning as principal, peer, or apprentice in each phase?

### 6. Backtracking & course-correction — how were mistakes and dead-ends handled?

Frameworks: 5 Whys · bisection · Chesterton's fence (understand before removing) · rubber-ducking · blameless post-mortem.

Probes: Moments where direction changed. How was the pivot decided? How was prior work salvaged or discarded? How was accountability distributed when something broke or missed?

---

## Step 3 — Distil to principles

For each lens, write **one to three concise principles** that are:

- **Imperative and specific** — "Propose two options before executing when the choice is reversible," not "be collaborative."
- **Grounded in observed evidence** — drawn from what actually happened, not from generic best practice.
- **Operationally actionable** — pass the test: *would future-Claude know what to do differently because of this line?*

Total target: **10–18 principles across all six lenses, fitting on roughly one page** (~400–700 words of principles). The page-fit is the binding constraint; cut whatever doesn't fit.

Why concise: the output is meant to be loaded into a future session's context. Bloat defeats the purpose.

---

## Step 4 — Name the skill from its content

The skill name MUST be derived from the actual extracted norms, not from a generic template. `way-of-working` is the name of *this* parent skill (the extractor); the *output* skill is named after the dominant ethos that emerged from analysis.

Rules:

- **kebab-case, 2–4 words, lowercase.** `root-cause-first`, `tracer-bullet-mode`, `pair-debug-cadence`, `evidence-bound-review`, `tdd-strict`. Not `way-of-working`, not `our-style`, not `collab1`.
- **Name the ethos, not the activity of extraction.** "What is the single rule that, if violated, would feel most wrong to the user?" That rule names the skill.
- **If naming is not obvious, either ask now or surface the alternatives inside the Step 5 presentation.** One short message: "I'd name this `X` — captures `<ethos>`. Alternatives: `Y`, `Z`. Pick?" Either path is fine — pick whichever costs less for the user.
- **Reject generic names.** If the proposed name could apply equally well to any other extraction (e.g. `collaboration-style`, `our-way`, `how-we-work`, `effective-mode`), the analysis was too shallow — go back to Step 3 and re-distil until a specific ethos surfaces.

Confirmed name is `<skill-name>` for the rest of these instructions.

---

## Step 4.5 — Overlap check against existing skills

Before presenting, scan for existing skills that already cover the proposed ethos in part or in full. Skipping this step risks shipping a duplicate or a skill that should have been a merge.

Scan scope:

- **Marketplace plugins in this repo** — `claude/plugins/*/skills/*/SKILL.md` (siblings of `extract-way-of-working`).
- **User-level skills** — `~/.claude/skills/*/SKILL.md` if that directory exists.
- **Project-level skills** — `<repo>/.claude/skills/*/SKILL.md` if applicable.
- **Currently loaded skill list** — the session's available-skills system reminder (already in context; no fetch needed).

For each candidate, compare the proposed name + ethos + signature moves against the candidate's description and principles. Classify each match as:

- **Full overlap** — existing skill already does this. Recommend: *skip extraction; point user to `<existing-skill-name>`.*
- **Partial overlap** — existing skill covers part of the ethos. Recommend one of:
  - **(a) narrow** — scope the new skill to the non-overlapping part,
  - **(b) merge** — edit the existing skill instead of creating a new one,
  - **(c) proceed** — only if the framings are genuinely distinct.

  State which option you recommend and why.
- **No overlap** — proceed cleanly.

Overlap findings are surfaced in Step 5 and feed into the worth-of-extraction estimate.

---

## Step 5 — Present extraction summary & get approval

**No files are written before this step's approval gate clears.** Scratch notes in memory/context are fine; on-disk artifacts are not.

Present a single scannable message with the following sections:

1. **Proposed skill name** + 1-line ethos (from Step 4). If naming was uncertain and the user has not yet chosen, list alternatives here and ask.
2. **What this skill will help with** — when future-Claude should load it, what behavior change it produces, what kinds of tasks it covers. 3–5 bullets.
3. **What it will NOT do** — boundaries, so the user can spot misframing.
4. **Principles preview** — the 10–18 distilled principles grouped by the six lenses (compact list, not the final formatted SKILL.md).
5. **Overlap with existing skills** (from Step 4.5) — list any full or partial matches by name + path, with recommendation: *skip / narrow / merge / proceed*.
6. **Worth-of-extraction estimate** — one of:
    - *Worth extracting* — distinct, transferable ethos with friction-grounded evidence and no significant overlap.
    - *Marginal* — recognizable patterns but overlap with an existing skill, or thin evidence; flag the risk and let the user decide.
    - *Not worth extracting* — too generic, too short, or fully covered by an existing skill; recommend skip and explain why.
7. **Source** — transcript file path or session ID + ISO date.

**Ambiguity branch:** if after Step 2–4 the ethos does not resolve into a specific, name-able pattern, **do not guess**. Ask one focused question — *"What were you hoping to capture by extracting this — the [X] pattern, the [Y] pattern, or something else?"* — re-distil, then present.

**Approval gate:** close the message with — *"Proceed to write the skill, revise, rename, or skip?"* — and **wait** for an explicit answer.

- **On revise/rename:** loop back to Step 3 or 4 and re-present.
- **On skip:** stop. Return the summary + reasoning only — no files.
- **On proceed:** go to Step 6.

---

## Step 6 — Package as a skill

Create the new skill at:

- **Inside the `agentic-kelzenberg` marketplace repo** (detect by `.claude-plugin/marketplace.json` at repo root naming `agentic-kelzenberg`): write to `claude/plugins/way-of-working/skills/<skill-name>/SKILL.md`. The new skill becomes a sibling of `extract-way-of-working` and ships with the `way-of-working` plugin automatically — no edits to `marketplace.json` or `plugin.json` required.
- **Inside any other project repo:** `<repo>/.claude/skills/<skill-name>/`.
- **Otherwise (default in Cowork):** `<outputs-dir>/<skill-name>/`.

Do not overwrite or shadow `extract-way-of-working`. If the content-derived skill name from Step 4 collides with it, return to Step 4 and pick a different name — the extractor must never be replaced by one of its own outputs.

Structure:

```
<skill-name>/
└── SKILL.md
```

Use this template for `SKILL.md` (replace `<skill-name>` and `<Skill Title>` with the chosen name in kebab and title case; trigger phrases must match the actual extracted ethos — not the generic placeholders below):

```markdown
---
name: <skill-name>
description: <One sentence stating the ethos and when it applies, written so a future session knows whether to load this.> Trigger phrases: "<phrase 1>", "<phrase 2>", "<phrase 3>".
---

# <Skill Title>

## Source
Extracted from: <transcript file path or session ID + date>
Extraction date: <YYYY-MM-DD>

## Operating principles

### Decision-making
- <principle 1>
- <principle 2>

### Technical approach
- <principle 1>
- <principle 2>

### Workflow rituals
- ...

### Sparring & challenge
- ...

### Role distribution
- ...

### Backtracking
- ...

## Signature moves
Two to four specific moves that defined this collaboration. Each should name a recognizable behavior, not a value.
Example: "Always propose a falsifiable verification step before declaring done."

## What this is NOT
Two to three things to avoid that were notably absent or actively unhelpful when tried.
Example: "Do not produce long markdown reports in chat — the user prefers prose answers with deliverables saved to files."
```

---

## Step 7 — Self-verify before declaring done

Run all seven checks. Failing any one means revising before output.

1. **Approval check** — the user explicitly approved at the Step 5 gate. If not, you should not have written files; stop and return to Step 5.
2. **Evidence check** — every principle has a citeable turn-reference. If not, drop or weaken the line.
3. **Specificity check** — would the principle apply to literally any conversation? If yes, sharpen or cut.
4. **Length check** — the assembled `SKILL.md` fits on one screen.
5. **Anti-platitude check** — search the draft for: *collaborative, clear communication, helpful, thorough, robust, effective, productive*. If any of these appear without a specific behavioral cash-out in the same line, rewrite.
6. **Friction check** — at least one principle is grounded in a *friction* moment (pushback, course-correction, disagreement). If the extraction reads as uniformly positive, the disconfirming evidence has been ignored — and that is where the real norms live.
7. **Name check** — the skill name is content-derived, not the literal string `way-of-working` or any equivalent generic placeholder. The name and the description's trigger phrases reference the actual extracted ethos.

---

## Anti-patterns to avoid

- Listing what *Claude* did well. The artifact is about *how they worked together*, not a Claude performance review.
- Recency bias — over-weighting the last few turns of the source conversation.
- Confirmation bias — assuming everything in the conversation worked. Friction moments reveal working norms most clearly.
- Generic prompt-engineering advice that has no link to this specific dyad.
- Naming a framework ("applied Cynefin") without showing the behavior it implies.

---

## Output

There are two distinct return moments.

### Pre-write return — end of Step 5 (before any files exist)

The presentation message itself: proposed name, what-it-helps-with, what-it-is-NOT, principles preview, overlap findings, worth-of-extraction estimate, source — closed by the approval question *"Proceed to write the skill, revise, rename, or skip?"*. Nothing is written to disk yet.

### Post-write return — after Step 7 (only on user approval)

Return three things in this order:

1. The path to the new skill directory.
2. A five-line prose summary of the signature collaboration mode that was found.
3. The one question to ask the user to validate the extraction — phrased so a yes/no or short answer can confirm or correct the read.
