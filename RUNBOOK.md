HUMAN-ONLY. Do not point Claude at this file; it holds rationale, not instructions.

# Running SPEC.md in Claude Code

Plan -> Execute -> Verify -> Audit -> Repeat, with a model per stage.

## Setup (once)

Copy into the project root:

    CLAUDE.md                      standing constraints, loaded every turn
    .claude/agents/sf-verify.md    deploy + test runner  (sonnet)
    .claude/agents/sf-audit.md     spec compliance       (opus)
    .claude/agents/Explore.md      overrides built-in    (haiku)
    SPEC.md                        the specification

Restart Claude Code after creating `.claude/agents/` for the first time - a
running session does not detect a newly created agents directory.

## Why this shape is the token-efficient one

The dominant cost in a repair loop is not prompt length. It is context
accumulation: deploy output and test output are enormous, mostly noise, and
once in the main window they are re-sent on every subsequent turn for the rest
of the session. A ten-iteration loop that keeps raw CLI output in the main
thread pays for that output ten times over, growing each time.

Subagents run in their own context and return only their final message. So the
verifier reads a 400-line deploy log and returns six lines. The main thread
never sees the other 394. That single move is worth more than every prompt
tightening combined.

Second lever: output tokens cost roughly five times input tokens, so the
expensive failure is regenerating a file rather than editing it. Hence the
instruction to work in diffs, and the deliberate choice to run execution on
Sonnet - the stage that emits the most tokens should not be the most expensive
per token.

Third: standing constraints belong in CLAUDE.md, not in prompts. Restating the
User-lookup rule in every turn pays for it every turn. In CLAUDE.md it sits in
the cache-stable prefix.

Note that a fork (`/subtask`) shares the parent's prompt cache, whereas a named
subagent has a separate cache. Forks are cheaper when the task needs the whole
conversation; named subagents are cheaper when it does not. Verification does
not, so it stays a named subagent.

## Model per stage

| Stage   | Model  | Why                                                          |
|---------|--------|--------------------------------------------------------------|
| Plan    | opus   | Architecture and sequencing. Wrong here is expensive later.  |
| Execute | sonnet | High output volume, low judgement. Cheapest per output token.|
| Verify  | sonnet | Error classification is judgement, but narrow and scripted.  |
| Audit   | opus   | Finds what compiles but is wrong. Needs the strongest model. |
| Explore | haiku  | Mechanical search. Overrides built-in, which inherits opus.  |

Set the main session with `/model opusplan` if available: Opus while planning,
Sonnet once execution starts, automatically.

## The loop

Per stage of the build, not per file:

1. PLAN     - opus, plan mode. Produce the stage's file list and test list.
              Approve before any edit.
2. EXECUTE  - sonnet. Make the changes. Diffs only.
3. VERIFY   - `@sf-verify`. Returns STATUS / CAUSES / SYMPTOMS / TESTS / NEXT.
4. If not clean: fix ONE cause, return to 3. Never fix symptoms.
5. AUDIT    - `@sf-audit` once verify is clean. Behaviour vs spec.
6. If gaps: return to 2. Otherwise next stage.

Stop conditions: `sf-verify` reports REPEAT, or ten iterations elapse, or a fix
would violate CLAUDE.md. Halt and report; do not keep looping.

## Suggested stages

Sequenced so each is independently verifiable:

1. Delete the old build (projector, board, controller, dead fields/objects)
2. Objects and fields, permission sets
3. Seed script, 10 tasks
4. Apex: query layer + archive process
5. LWC: day tabs + pending list, read-only
6. LWC: time logging, edit, delete
7. Complete/untick, past-week navigation, completed section

## Kickoff prompt

Paste this as the first message:

---
Read SPEC.md, CLAUDE.md and LOOP.md. Do not write any code yet.

Read LOOP.md and follow it exactly.

Where SPEC.md is silent or ambiguous, ask. Do not choose a default silently.

Start with stage 1: tell me exactly what you would delete and why, and what
depends on each item.
---

## What this does not do

It guarantees the code compiles, deploys, and passes its tests. It does not
guarantee the behaviour matches the spec - that is what the audit stage is for,
and even that is weaker than opening the page and using it.

The capacity meter in the previous build deployed cleanly, passed every test,
and rendered an overbooked day as half empty for three iterations.
