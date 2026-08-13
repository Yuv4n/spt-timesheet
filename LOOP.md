Per stage, not per file:

1. PLAN (plan mode). File list + test list. Wait for approval.
2. EXECUTE. Diffs only.
3. @sf-verify. Fix only what it names CAUSE, one per iteration. Never symptoms.
4. @sf-audit once verify is clean. Fix GAPS. Then stop and report.

Never run deploy or test commands yourself - always @sf-verify, so the output
stays out of this conversation.

Halt and report if: sf-verify says REPEAT, 10 iterations pass, a fix would
violate CLAUDE.md, or SPEC.md is silent on something the fix depends on.

Stages:
1. Delete old build (projector, board, controller, dead fields/objects)
2. Objects, fields, permission sets
3. Seed script, 10 tasks
4. Apex: query layer + archive process
5. LWC: day tabs + pending list, read-only
6. LWC: time logging, edit, delete
7. Complete/untick, past-week navigation, completed section
