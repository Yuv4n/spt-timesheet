/**
 * THE SEAM.
 *
 * Every read from and write to timesheet data goes through this interface and
 * nowhere else. In the dev org it is backed by Timesheet_Entry__c. In the SPT
 * sandbox it will be backed by whatever actually exists there - FSL's
 * TimeSheetEntry, or SPT's own custom object.
 *
 * When that answer arrives, ONE new implementation class is written and the
 * factory is pointed at it. No controller and no LWC changes.
 *
 * Do not add timesheet field references anywhere outside implementations of
 * this interface.
 */
public interface ITimesheetService {

    /**
     * Record actual time against a planning item.
     * @param itemId   The Planning_Item__c the time was spent on.
     * @param minutes  Actual minutes spent.
     * @param caseId   Case to bill against, or null for internal work.
     * @param billable Whether this time is billable.
     */
    void logActuals(Id itemId, Integer minutes, Id caseId, Boolean billable);

    /**
     * Minutes already logged for a set of planning items.
     * Used to reconcile the plan against reality.
     */
    Map<Id, Integer> getLoggedMinutes(Set<Id> itemIds);
}
