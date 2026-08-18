/**
 * Shared test data.
 */
@IsTest
public class PlannerTestData {

    public static Planning_Item__c item(String name, Id assigneeId, Decimal estimate) {
        return new Planning_Item__c(
            Name = name,
            Assignee__c = assigneeId,
            Estimate_Minutes__c = estimate,
            Status__c = 'Not Started'
        );
    }

    public static Timesheet_Entry__c entry(Id taskId, Date entryDate, Integer minutes) {
        return new Timesheet_Entry__c(
            Task__c = taskId,
            Entry_Date__c = entryDate,
            Minutes__c = minutes
        );
    }
}
