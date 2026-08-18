/**
 * THE SEAM.
 *
 * Every read from and write to individual time-entry records goes through
 * this interface and nowhere else. In the dev org it is backed by
 * Timesheet_Entry__c. In the SPT sandbox it will be backed by whatever
 * actually exists there - FSL's TimeSheetEntry, or SPT's own custom object.
 *
 * When that answer arrives, ONE new implementation class is written and the
 * factory is pointed at it. No controller and no LWC changes.
 *
 * Business rules (current-week-only edits, duration limits, locking a
 * complete task) live in the controller, above this seam, since they apply
 * regardless of which backend is plugged in. This interface is deliberately
 * a plain CRUD-ish seam, not a rules engine.
 *
 * Do not add timesheet-entry field references anywhere outside
 * implementations of this interface.
 */
public interface ITimesheetService {

    /** Always creates a new entry - logging the same task twice on one day never merges. */
    Id logEntry(Id taskId, Date entryDate, Integer minutes);

    void updateEntry(Id entryId, Date entryDate, Integer minutes);

    void deleteEntry(Id entryId);

    /** Null if the entry doesn't exist or isn't visible to the running user. */
    PlannerModels.TimeEntry getEntry(Id entryId);

    /** All of one user's entries across a date range, for day-tab display. */
    List<PlannerModels.TimeEntry> getEntriesForRange(Id userId, Date fromDate, Date toDate);
}
