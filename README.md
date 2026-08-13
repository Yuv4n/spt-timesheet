# SPT Planner - scaffold

Skeleton for the timesheet optimiser. Built to be pushed through the pipeline
early, while the stakes are low, not to be feature complete.

## READ THIS FIRST - decision 1

The object API names in this scaffold are **placeholders**:
`Planning_Item__c`, `Capacity__c`, `Absence__c`.

Confirm SPT's naming convention and check for existing objects of the same name
BEFORE deploying anywhere shared. Labels can be changed freely afterwards; API
names cannot - renaming breaks every Apex, LWC, permission set and layout
reference. If SPT prefixes custom objects, do a find-replace across this repo
now, not later.

## The seam

`ITimesheetService` is the only place timesheet fields are referenced.
`LocalTimesheetService` is a dev-org placeholder that writes actuals onto
`Planning_Item__c` because the dev org has no timesheet object.

When blocking question 1 is answered (FSL `TimeSheetEntry` vs SPT custom
object), write one new class implementing `ITimesheetService` and change one
line in `TimesheetServiceFactory`. Nothing else moves.

**Do not reference timesheet fields anywhere outside an implementation of that
interface.** That is the whole point of the structure.

## Structure

```
force-app/main/default/
  objects/          Planning_Item__c, Capacity__c, Absence__c
  classes/
    PlannerModels             DTOs, no SOQL/DML
    ScheduleProjector         pure push-down logic - all the real bugs live here
    PlannerBoardController    board payload in one round trip
    ITimesheetService         the seam
    LocalTimesheetService     dev-org placeholder
    TimesheetServiceFactory   single point of implementation choice
    *Test                     ScheduleProjectorTest is the important one
  lwc/plannerBoard/           READ ONLY board - slice one, no drag and drop yet
  permissionsets/             SPT_Planner, SPT_Team_Member
scripts/apex/seed.apex        seed data, includes deliberate broken records
```

## Setup

```bash
sf org login web --alias spt-dev --set-default
sf project deploy start --target-org spt-dev
sf org assign permset --name SPT_Planner --target-org spt-dev
sf apex run --file scripts/apex/seed.apex --target-org spt-dev
sf apex run test --target-org spt-dev --test-level RunLocalTests --result-format human --code-coverage --wait 10
```

Then add the `plannerBoard` component to a Lightning App Page and set the
`userIds` property to your own User Id.

## Before any deploy to a shared org

```bash
sf project deploy start --dry-run --test-level RunLocalTests --target-org spt-sandbox
```

Validation-only. Runs the full deploy and the whole test suite without
committing anything. Do this every time. Production requires 75% Apex coverage
as a hard gate - the deploy fails below it.

## Pipeline

1. Build in dev org, commit to git
2. **Code review on the PR** - before the sandbox deploy, not after
3. Deploy to sandbox (dry run first)
4. Functional review in sandbox against real data
5. Deploy to production from git

Git is the source of truth. Never edit in production - once you do, git stops
matching reality and the next deploy overwrites someone's live change.

## What will break on the sandbox move, and that is expected

- `seed.apex` will fail. SPT's Case object will have required custom fields,
  validation rules and probably triggers this org does not have.
- Object name collisions - see decision 1.
- Field-level security. If the permission sets are not in the deployment, the
  page loads and shows nothing.
- The `Billable__c` checkbox may be redundant if SPT already derives
  billability from the Case. Check before building on it.

## Gotchas already hit

- **Required lookups need `<deleteConstraint>`.** A `<required>true</required>`
  Lookup must specify `Restrict` or `Cascade` or the field fails to deploy.
  Both `User__c` lookups use `Restrict` - you cannot orphan capacity or absence
  records by removing a user.
- Salesforce deploys are all-or-nothing. One bad field reports every dependent
  Apex class, test and LWC as its own error. Read the error list bottom-up:
  metadata errors are causes, "dependent class is invalid" and "unable to find
  Apex action class" are symptoms.

## Design rule: dates are computed, not stored

`Scheduled_Date__c` is written only for PINNED work. Everything else gets its
date from `ScheduleProjector`, derived from sequence order and capacity.
`reorder()` therefore writes sequence and assignee only.

If you later add drag-to-a-specific-day, this rule has to change deliberately -
writing a date the projector ignores would make the board lie about what it is
doing.

## Platform rule learned the hard way

**A required lookup to `User` is impossible in Salesforce.**

- A `<required>true</required>` Lookup must declare `<deleteConstraint>`.
- A lookup whose `<referenceTo>` is `User` is forbidden from declaring one -
  Users are deactivated, never deleted, so there is no delete behaviour.

The two constraints are mutually exclusive. `Capacity__c.User__c` and
`Absence__c.User__c` are therefore optional lookups, with the requirement
enforced by a `User_Is_Required` validation rule on each object. Same behaviour
for the user, legal metadata for the platform.

`relationshipName` must also be unique per parent object. Both use a
`Planner_` prefix to avoid colliding with anything else on `User`.

## Audit fixes applied

- Required lookups now carry `<deleteConstraint>Restrict</deleteConstraint>`.
- Zero-capacity days (absences) are skipped by the projector. Previously an
  empty absence day counted as "untouched" and accepted work.
- Completed work scheduled in the current week stays on the board. Previously
  `Status__c != 'Done'` removed it, so an overrun stopped pushing later work
  down the moment it was marked done.
- `userIds` is a setter feeding a real field. A wire's `$parameter` must point
  at a field, not a getter.
- `targetConfigs` added so `userIds` is settable in App Builder.

Second audit pass:

- `getWeek` returns an empty board for a null/empty user list instead of binding
  null into SOQL.
- Board query is bounded to the displayed week, so next week's plan no longer
  leaks into this week's projection, and carries a `LIMIT` guard.
- `reorder()` no longer writes `Scheduled_Date__c` and no longer restarts
  sequence numbering per day (which collided across days).
- Weekday names computed from a date offset, not `DateTime.format('EEEE')`,
  which returns the running user's LOCALE name - a German or French locale
  matched no `Capacity__c` picklist value and silently gave everyone zero hours.
- Absence expansion clamped to the requested window.
- A Case the running user cannot read is flagged as unverified rather than
  assumed billable.
- `logActuals` returns a usable message instead of "List has no rows".
- `LocalTimesheetService` uses `update as user` rather than a partial manual FLS
  check followed by system-mode DML.
- Pinned work dated outside the displayed week is flagged, never silently
  re-placed.

## Known deliberate omissions

- No drag and drop. Grid vs list is still an open decision (blocking question
  5) and the interaction layer is the part most likely to be thrown away.
- No publish state, no notifications, no carry-over automation.
- No analytics. Charts built on seeded data tell you nothing.
- No SOW/budget model. Depends on blocking question 8, which may make budget a
  hard scheduling constraint and change the capacity model.

## Scheduling behaviour, in one sentence

Walk a person's items in sequence order; each consumes its actual hours if
recorded, otherwise its estimate; when a day runs out of capacity the next item
rolls to the following day; pinned items never move; work is never reassigned
between people and never reordered by priority automatically.
