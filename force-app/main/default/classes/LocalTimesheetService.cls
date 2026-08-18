/**
 * Dev-org implementation of ITimesheetService, backed by Timesheet_Entry__c.
 *
 * NOT the sandbox implementation. See SandboxTimesheetService (to be written
 * once the real schema is known - FSL's TimeSheetEntry, or SPT's own object).
 */
public with sharing class LocalTimesheetService implements ITimesheetService {

    public Id logEntry(Id taskId, Date entryDate, Integer minutes) {
        if (taskId == null || entryDate == null || minutes == null || minutes <= 0) {
            throw new TimesheetException('logEntry requires a task, a date, and positive minutes');
        }
        Timesheet_Entry__c entry = new Timesheet_Entry__c(
            Task__c = taskId,
            Entry_Date__c = entryDate,
            Minutes__c = minutes
        );
        insert as user entry;
        return entry.Id;
    }

    public void updateEntry(Id entryId, Date entryDate, Integer minutes) {
        if (entryId == null || entryDate == null || minutes == null || minutes <= 0) {
            throw new TimesheetException('updateEntry requires an entry id, a date, and positive minutes');
        }
        update as user new Timesheet_Entry__c(
            Id = entryId,
            Entry_Date__c = entryDate,
            Minutes__c = minutes
        );
    }

    public void deleteEntry(Id entryId) {
        if (entryId == null) {
            throw new TimesheetException('deleteEntry requires an entry id');
        }
        delete as user new Timesheet_Entry__c(Id = entryId);
    }

    public PlannerModels.TimeEntry getEntry(Id entryId) {
        List<Timesheet_Entry__c> found = [
            SELECT Id, Task__c, Task__r.Name, Entry_Date__c, Minutes__c
            FROM Timesheet_Entry__c
            WHERE Id = :entryId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : toDto(found[0]);
    }

    public List<PlannerModels.TimeEntry> getEntriesForRange(Id userId, Date fromDate, Date toDate) {
        List<PlannerModels.TimeEntry> result = new List<PlannerModels.TimeEntry>();
        for (Timesheet_Entry__c e : [
            SELECT Id, Task__c, Task__r.Name, Entry_Date__c, Minutes__c
            FROM Timesheet_Entry__c
            WHERE Task__r.Assignee__c = :userId
              AND Entry_Date__c >= :fromDate AND Entry_Date__c <= :toDate
            WITH USER_MODE
            ORDER BY Entry_Date__c
        ]) {
            result.add(toDto(e));
        }
        return result;
    }

    private PlannerModels.TimeEntry toDto(Timesheet_Entry__c e) {
        PlannerModels.TimeEntry dto = new PlannerModels.TimeEntry();
        dto.entryId = e.Id;
        dto.taskId = e.Task__c;
        dto.taskName = e.Task__r.Name;
        dto.entryDate = e.Entry_Date__c;
        dto.minutes = e.Minutes__c == null ? null : (Integer) e.Minutes__c;
        return dto;
    }

    public class TimesheetException extends Exception {}
}
