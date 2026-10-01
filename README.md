# SPT Planner - scaffold

Skeleton for the timesheet optimiser.

## The seam

`ITimesheetService` is the only place timesheet fields are referenced.
`LocalTimesheetService` is a dev-org placeholder that writes actuals onto
`Planning_Item__c` because the dev org has no timesheet object.

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

## Pipeline

1. Build in dev org, commit to git
2. **Code review on the PR** - before the sandbox deploy, not after
3. Deploy to sandbox (dry run first)
4. Functional review in sandbox against real data
5. Deploy to production from git

## What will break on the sandbox move, and that is expected

- `seed.apex` will fail. SPT's Case object will have required custom fields,
  validation rules and probably triggers this org does not have.
- Object name collisions.
- Field-level security. If the permission sets are not in the deployment, the
  page loads and shows nothing.
- The `Billable__c` checkbox may be redundant if SPT already derives
  billability from the Case.

## Design rule: dates are computed, not stored

`Scheduled_Date__c` is written only for PINNED work. Everything else gets its
date from `ScheduleProjector`, derived from sequence order and capacity.
`reorder()` therefore writes sequence and assignee only.

## Scheduling behaviour, TL;DR

Walk a person's items in sequence order; each consumes its actual hours if
recorded, otherwise its estimate; when a day runs out of capacity, the next item
rolls to the following day; pinned items never move; work is never reassigned
between people and never reordered by priority automatically.
