/**
 * Dev-org implementation of ITimesheetService.
 *
 * PLACEHOLDER. This writes actuals straight onto Planning_Item__c because the
 * dev org has no timesheet object. It exists so the rest of the system can be
 * built and tested before blocking question 1 is answered.
 *
 * It is NOT the sandbox implementation. See SandboxTimesheetService (to be
 * written once the real schema is known).
 */
public with sharing class LocalTimesheetService implements ITimesheetService {

    public void logActuals(Id itemId, Integer minutes, Id caseId, Boolean billable) {
        if (itemId == null || minutes == null || minutes < 0) {
            throw new TimesheetException('logActuals requires an item id and non-negative minutes');
        }
        Planning_Item__c item = new Planning_Item__c(
            Id = itemId,
            Actual_Minutes__c = minutes,
            Status__c = 'Done'
        );
        // `as user` enforces CRUD and FLS in one place. The previous manual
        // isUpdateable() check was both redundant and incomplete - it checked one
        // field and then did a system-mode DML that ignored the answer.
        update as user item;
    }

    public Map<Id, Integer> getLoggedMinutes(Set<Id> itemIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        for (Planning_Item__c item : [
            SELECT Id, Actual_Minutes__c
            FROM Planning_Item__c
            WHERE Id IN :itemIds
            WITH USER_MODE
        ]) {
            result.put(item.Id, item.Actual_Minutes__c == null ? 0 : (Integer) item.Actual_Minutes__c);
        }
        return result;
    }

    public class TimesheetException extends Exception {}
}
