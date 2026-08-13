SPT Timesheet - member view spec v1.0

WHAT THIS IS: a timesheet capture tool with weekly assignment on top. NOT a scheduler.
Nobody plans days in advance. Members record what they actually did, after the fact.

Scope for this build: member experience only. Raj's view is out of scope.
Task source is a seed script of 10 real records, behind a seam so real assignment
can replace it later.

## Confirmed decisions

Product shape
1. Raj assigns tasks to people weekly, with NO dates. (His UI is out of scope.)
2. Estimated time is a displayed guideline. Stored, never enforced.
3. Members record time against a task on a specific day, after the work happened.
4. There is no capacity target, no over-capacity warning, no push-down, no projection.
5. Planning period is ONE WEEK, fixed.

Data model
6. Task: name, estimate, owner, complete flag, member-created flag, completion timestamp.
7. Time entry: child of task. Date + minutes. Many per task. Many per task per day.
8. Estimate entered and displayed as hours and minutes ("2h 30m"). Stored as minutes.
9. Estimate is REQUIRED on member-created tasks. [DEFAULT TAKEN - confirm]

Member view - layout
10. Seven day tabs (Mon-Sun), current week.
11. Pending list always visible alongside the tabs.
12. Pending list = all incomplete tasks owned by the member. This week's and rolled
    over, undifferentiated. There is NO separate backlog section.
13. Each pending task shows total time logged so far.
14. Each day tab shows its total logged time. No target, no warning, no comparison.

Member view - ordering
15. Pending list ordered by remaining time ASCENDING, where remaining = estimate
    minus time logged.
16. Overrunning tasks go negative and therefore sort to the very top. This is
    intended - overruns should be the most visible thing on screen.

Time logging
17. Duration chosen from a dropdown in 15-minute increments, 15 min to 12 hours.
18. Logging the same task twice on one day creates TWO SEPARATE entries. No merging.
19. Entries can be edited and deleted freely within the current week.
20. Future day tabs are READ-ONLY. On Tuesday, Thursday cannot be logged against.
21. A logged task STAYS in the pending list. It does not move into the day.

Task lifecycle
22. Members can create their own tasks. Fields: name and estimate only.
23. Members can RENAME their own tasks. They cannot rename Raj's assigned tasks.
24. NO TASK CAN BE DELETED, by anyone, ever.
25. Ticking complete makes the task read-only for time logging.
26. Unticking reopens it for logging.
27. A ticked task REMAINS in the pending list until the week actually passes.

Week end
28. An archive process moves completed tasks into a collapsible, read-only
    "Completed tasks" section.
29. Completed tasks ordered MOST RECENTLY COMPLETED FIRST.
30. Completed section shows a rolling last 30 days. [DEFAULT TAKEN - confirm]
31. Incomplete tasks are untouched - they stay assigned and simply carry on.
32. Archive is triggered MANUALLY for now, scheduled later.
33. Manual trigger is an Apex script run from the CLI. [DEFAULT TAKEN - confirm]

Week navigation
34. Members can view PAST weeks, read-only.
35. A past week shows day tabs with that week's entries only. NO pending list.
36. Members cannot navigate to future weeks.

## To be deleted from the existing build

- ScheduleProjector (entire class + tests)
- plannerBoard LWC
- PlannerBoardController
- Planning_Item__c fields: Scheduled_Date__c, Sequence__c, Pinned__c
- Capacity__c object (no capacity concept remains)
- Absence__c object (nothing consumes it)

Keep: PlannerModels (reshaped), ITimesheetService + factory (the timesheet seam),
Planning_Item__c core fields, both permission sets (reshaped).

## Open decisions - must be answered before this touches real timesheets

A. Can member-created tasks be Case-linked and billable?
   PLACEHOLDER IN USE: internal and non-billable only.
   This is the highest-risk open item - a member creating billable time without
   Raj seeing it has revenue and audit consequences.

B. Confirm requirement 9 (estimate mandatory).
C. Confirm requirement 30 (rolling 30 days).
D. Confirm requirement 33 (CLI script trigger).

## Derived requirements not in the source document

- Completion timestamp field, required to order the Completed section (req 29).
- Member-created flag, required to gate renaming (req 23).
- Time entries must survive independently of task state, since tasks are never
  deleted and past weeks remain viewable.
- The seed script assigns all 10 tasks to the running user.
- Members see only their own tasks and entries.
