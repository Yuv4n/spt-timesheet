/**
 * Shared test data.
 */
@IsTest
public class PlannerTestData {

    public static Planning_Item__c item(String name, Id assigneeId, Decimal estimate) {
        return new Planning_Item__c(
            Name = name,
            Item_Type__c = 'Internal',
            Assignee__c = assigneeId,
            Estimate_Hours__c = estimate,
            Priority__c = 'P2',
            Status__c = 'Not Started'
        );
    }
}
