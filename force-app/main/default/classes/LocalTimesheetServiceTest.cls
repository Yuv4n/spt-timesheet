@IsTest
private class LocalTimesheetServiceTest {

    @IsTest
    static void logEntryCreatesANewRow() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;

        Id entryId = new LocalTimesheetService().logEntry(task.Id, Date.today(), 30);

        Timesheet_Entry__c saved = [SELECT Task__c, Entry_Date__c, Minutes__c FROM Timesheet_Entry__c WHERE Id = :entryId];
        Assert.areEqual(task.Id, saved.Task__c, 'Linked to the right task');
        Assert.areEqual(30, saved.Minutes__c, 'Minutes recorded');
    }

    @IsTest
    static void loggingTwiceCreatesTwoSeparateEntries() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        ITimesheetService svc = new LocalTimesheetService();

        svc.logEntry(task.Id, Date.today(), 30);
        svc.logEntry(task.Id, Date.today(), 30);

        Assert.areEqual(2, [SELECT COUNT() FROM Timesheet_Entry__c WHERE Task__c = :task.Id], 'No merging');
    }

    @IsTest
    static void updateEntryChangesMinutesAndDate() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Id entryId = new LocalTimesheetService().logEntry(task.Id, Date.today(), 30);

        new LocalTimesheetService().updateEntry(entryId, Date.today().addDays(-1), 45);

        Timesheet_Entry__c saved = [SELECT Entry_Date__c, Minutes__c FROM Timesheet_Entry__c WHERE Id = :entryId];
        Assert.areEqual(45, saved.Minutes__c, 'Minutes updated');
        Assert.areEqual(Date.today().addDays(-1), saved.Entry_Date__c, 'Date updated');
    }

    @IsTest
    static void deleteEntryRemovesTheRow() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Id entryId = new LocalTimesheetService().logEntry(task.Id, Date.today(), 30);

        new LocalTimesheetService().deleteEntry(entryId);

        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Entry__c WHERE Id = :entryId]);
    }

    @IsTest
    static void getEntriesForRangeScopesToUserAndDates() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        ITimesheetService svc = new LocalTimesheetService();
        svc.logEntry(task.Id, Date.today(), 30);
        svc.logEntry(task.Id, Date.today().addDays(-10), 15); // outside the requested range

        List<PlannerModels.TimeEntry> entries = svc.getEntriesForRange(
            me, Date.today().addDays(-1), Date.today().addDays(1)
        );

        Assert.areEqual(1, entries.size(), 'Only the in-range entry returned');
        Assert.areEqual(task.Id, entries[0].taskId, 'Correct task');
        Assert.areEqual(task.Name, entries[0].taskName, 'Task name carried through');
    }

    @IsTest
    static void getEntryReturnsNullWhenMissing() {
        Assert.isNull(new LocalTimesheetService().getEntry(null), 'No entry for a null id');
    }

    @IsTest
    static void negativeMinutesAreRejected() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        try {
            new LocalTimesheetService().logEntry(task.Id, Date.today(), -10);
            Assert.fail('Negative time should not be accepted');
        } catch (LocalTimesheetService.TimesheetException e) {
            Assert.isTrue(e.getMessage().contains('positive'), 'Clear error message');
        }
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
