# Design decisions

The current build captures member timesheets. The earlier scheduling projection and capacity model have been removed. The README describes the current member behaviour. The earlier specification was removed in a concurrent update.

The controller owns business rules: ownership checks, current-week edits and duration limits. `ITimesheetService` owns individual time-entry storage. The factory selects `LocalTimesheetService`, which uses `Timesheet_Entry__c`. A sandbox backend remains unimplemented until its schema is known.

Each log action creates a separate entry. Completion prevents new logging but still permits current-week entry corrections. Reopening clears the archive flag so the task returns to pending work. Completed tasks remain pending until the manual archiver processes a past completion week.

Queries and most entry writes use user-mode operations. Some task lifecycle fields are written in system context after controller checks. This is an implementation decision; deployment and access-control behaviour have not been validated against a live org in this review.

The repository includes three Apex test classes for the controller, local service and archiver. No test transcript or coverage report is checked in. The README lists commands for a development org without assuming a particular local alias.

The seed script clears planning items and their child time entries. It is a disposable-development setup tool. There is no production deployment or automatic archive schedule in this repository.
