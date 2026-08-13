@IsTest
private class LocalTimesheetServiceTest {

    @IsTest
    static void actualsAreRecordedAndTheItemIsClosed() {
        Planning_Item__c item = PlannerTestData.item('Task', UserInfo.getUserId(), 2);
        insert item;

        new LocalTimesheetService().logActuals(item.Id, 90, null, false);

        Planning_Item__c saved = [
            SELECT Actual_Minutes__c, Status__c FROM Planning_Item__c WHERE Id = :item.Id
        ];
        Assert.areEqual(90, saved.Actual_Minutes__c, 'Minutes recorded');
        Assert.areEqual('Done', saved.Status__c, 'Item closed');
    }

    @IsTest
    static void negativeMinutesAreRejected() {
        Planning_Item__c item = PlannerTestData.item('Task', UserInfo.getUserId(), 2);
        insert item;
        try {
            new LocalTimesheetService().logActuals(item.Id, -10, null, false);
            Assert.fail('Negative time should not be accepted');
        } catch (LocalTimesheetService.TimesheetException e) {
            Assert.isTrue(e.getMessage().contains('non-negative'), 'Clear error message');
        }
    }

    @IsTest
    static void loggedMinutesAreReadBack() {
        Planning_Item__c item = PlannerTestData.item('Task', UserInfo.getUserId(), 2);
        item.Actual_Minutes__c = 45;
        insert item;

        Map<Id, Integer> logged = new LocalTimesheetService().getLoggedMinutes(new Set<Id>{ item.Id });
        Assert.areEqual(45, logged.get(item.Id), 'Minutes read back');
    }

    @IsTest
    static void factoryReturnsTheLocalImplementationByDefault() {
        Assert.isInstanceOfType(
            TimesheetServiceFactory.getInstance(),
            LocalTimesheetService.class,
            'Dev org uses the local implementation'
        );
    }
}
