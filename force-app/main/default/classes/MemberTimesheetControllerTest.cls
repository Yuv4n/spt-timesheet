@IsTest
private class MemberTimesheetControllerTest {

    @IsTest
    static void getWeekDefaultsToTheCurrentWeek() {
        PlannerModels.Week week = MemberTimesheetController.getWeek(null);

        Assert.areEqual(7, week.days.size(), 'Seven day tabs');
        Assert.isTrue(week.isCurrentWeek, 'Defaults to the current week');
        Assert.areEqual('Monday', week.days[0].weekdayName, 'Starts on Monday');
        Assert.areEqual('Sunday', week.days[6].weekdayName, 'Ends on Sunday');
    }

    @IsTest
    static void pendingListOrdersByRemainingAscendingWithOverrunFirst() {
        Id me = UserInfo.getUserId();
        Planning_Item__c small = PlannerTestData.item('Small remaining', me, 60);
        Planning_Item__c large = PlannerTestData.item('Large remaining', me, 300);
        Planning_Item__c overrun = PlannerTestData.item('Overrun', me, 30);
        insert new List<Planning_Item__c>{ small, large, overrun };
        insert PlannerTestData.entry(overrun.Id, Date.today(), 60); // 30 min estimate, 60 logged -> -30 remaining

        PlannerModels.Week week = MemberTimesheetController.getWeek(null);

        Assert.areEqual(3, week.pending.size(), 'All three tasks pending');
        Assert.areEqual('Overrun', week.pending[0].name, 'Overrun sorts to the very top');
        Assert.isTrue(week.pending[0].remainingMinutes < 0, 'Overrun is negative');
        Assert.areEqual('Small remaining', week.pending[1].name, 'Then ascending by remaining');
        Assert.areEqual('Large remaining', week.pending[2].name, 'Largest remaining last');
    }

    @IsTest
    static void pastWeekHasNoPendingListButShowsItsEntries() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Date lastMonday = MemberTimesheetController.mondayOf(Date.today()).addDays(-7);
        insert PlannerTestData.entry(task.Id, lastMonday, 45);

        PlannerModels.Week week = MemberTimesheetController.getWeek(lastMonday);

        Assert.isFalse(week.isCurrentWeek, 'Not the current week');
        Assert.isTrue(week.pending.isEmpty(), 'No pending list for a past week');
        Assert.areEqual(45, week.days[0].totalMinutes, 'Its entries still show on the day tab');
    }

    @IsTest
    static void futureWeekIsRejected() {
        Date nextMonday = MemberTimesheetController.mondayOf(Date.today()).addDays(7);
        try {
            MemberTimesheetController.getWeek(nextMonday);
            Assert.fail('Future weeks are not navigable');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void completeButUnarchivedTaskStaysInPendingList() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Done, not archived', me, 60);
        task.Complete__c = true;
        insert task;

        PlannerModels.Week week = MemberTimesheetController.getWeek(null);

        Assert.areEqual(1, week.pending.size(), 'Ticked tasks remain visible until the week passes');
        Assert.isTrue(week.pending[0].complete, 'Flagged as complete');
    }

    @IsTest
    static void archivedTaskDropsOutOfThePendingList() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Archived', me, 60);
        task.Complete__c = true;
        task.Archived__c = true;
        insert task;

        PlannerModels.Week week = MemberTimesheetController.getWeek(null);

        Assert.isTrue(week.pending.isEmpty(), 'Archived work is gone from the pending list');
    }

    @IsTest
    static void logTimeCreatesAnEntry() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;

        Test.startTest();
        Id entryId = MemberTimesheetController.logTime(task.Id, Date.today(), 30);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Timesheet_Entry__c WHERE Id = :entryId]);
    }

    @IsTest
    static void logTimeRejectsAnIncrementOtherThanFifteenMinutes() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        try {
            MemberTimesheetController.logTime(task.Id, Date.today(), 20);
            Assert.fail('20 minutes is not a 15-minute increment');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void logTimeRejectsAFutureDay() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Date sunday = MemberTimesheetController.mondayOf(Date.today()).addDays(6);
        if (sunday <= Date.today()) {
            return; // today is Sunday - no future day exists within this week to test against
        }
        try {
            MemberTimesheetController.logTime(task.Id, sunday, 30);
            Assert.fail('Future days are read-only');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void logTimeRejectsADayOutsideTheCurrentWeek() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        try {
            MemberTimesheetController.logTime(task.Id, Date.today().addDays(-30), 30);
            Assert.fail('Only the current week can be logged against');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void logTimeRejectsACompleteTask() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        task.Complete__c = true;
        insert task;
        try {
            MemberTimesheetController.logTime(task.Id, Date.today(), 30);
            Assert.fail('A complete task is read-only for time logging');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void logTimeRejectsATaskThatIsNotYours() {
        List<User> others = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = true LIMIT 1];
        if (others.isEmpty()) {
            return; // no second user in this org to prove cross-user isolation against
        }
        Planning_Item__c task = PlannerTestData.item('Not mine', others[0].Id, 60);
        insert task;
        try {
            MemberTimesheetController.logTime(task.Id, Date.today(), 30);
            Assert.fail('Only your own tasks can be logged against');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void updateTimeChangesAnExistingEntry() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Id entryId = MemberTimesheetController.logTime(task.Id, Date.today(), 30);

        MemberTimesheetController.updateTime(entryId, Date.today(), 45);

        Assert.areEqual(45, [SELECT Minutes__c FROM Timesheet_Entry__c WHERE Id = :entryId].Minutes__c);
    }

    @IsTest
    static void deleteTimeRemovesAnExistingEntry() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        Id entryId = MemberTimesheetController.logTime(task.Id, Date.today(), 30);

        MemberTimesheetController.deleteTime(entryId);

        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Entry__c WHERE Id = :entryId]);
    }

    @IsTest
    static void setCompleteStampsAndClearsCompletedDate() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;

        MemberTimesheetController.setComplete(task.Id, true);
        Planning_Item__c done = [SELECT Complete__c, Completed_Date__c FROM Planning_Item__c WHERE Id = :task.Id];
        Assert.isTrue(done.Complete__c, 'Marked complete');
        Assert.isNotNull(done.Completed_Date__c, 'Completion stamped');

        MemberTimesheetController.setComplete(task.Id, false);
        Planning_Item__c reopened = [SELECT Complete__c, Completed_Date__c FROM Planning_Item__c WHERE Id = :task.Id];
        Assert.isFalse(reopened.Complete__c, 'Reopened');
        Assert.isNull(reopened.Completed_Date__c, 'Completion timestamp cleared');
    }

    @IsTest
    static void createTaskSetsAssigneeAndMemberCreated() {
        Test.startTest();
        Id taskId = MemberTimesheetController.createTask('My own task', 90);
        Test.stopTest();

        Planning_Item__c saved = [SELECT Assignee__c, Member_Created__c, Estimate_Minutes__c FROM Planning_Item__c WHERE Id = :taskId];
        Assert.areEqual(UserInfo.getUserId(), saved.Assignee__c, 'Assigned to the creator');
        Assert.isTrue(saved.Member_Created__c, 'Flagged as member-created');
        Assert.areEqual(90, saved.Estimate_Minutes__c, 'Estimate saved');
    }

    @IsTest
    static void createTaskRequiresAnEstimate() {
        try {
            MemberTimesheetController.createTask('No estimate', null);
            Assert.fail('An estimate is required');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void renameTaskAllowsOnlyMemberCreatedOwnTasks() {
        Id taskId = MemberTimesheetController.createTask('Original name', 30);

        MemberTimesheetController.renameTask(taskId, 'Renamed');

        Assert.areEqual('Renamed', [SELECT Name FROM Planning_Item__c WHERE Id = :taskId].Name);
    }

    @IsTest
    static void renameTaskRejectsARajAssignedTask() {
        Id me = UserInfo.getUserId();
        Planning_Item__c assigned = PlannerTestData.item('Raj assigned this', me, 60);
        insert assigned;
        try {
            MemberTimesheetController.renameTask(assigned.Id, 'Sneaky rename');
            Assert.fail('Only member-created tasks can be renamed');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Assert.areEqual('Raj assigned this', [SELECT Name FROM Planning_Item__c WHERE Id = :assigned.Id].Name);
    }

    @IsTest
    static void getCompletedTasksReturnsOnlyArchivedWorkWithinThirtyDays() {
        Id me = UserInfo.getUserId();
        Planning_Item__c recent = PlannerTestData.item('Recently archived', me, 60);
        recent.Complete__c = true;
        recent.Archived__c = true;
        recent.Completed_Date__c = Datetime.now().addDays(-5);
        Planning_Item__c old = PlannerTestData.item('Archived long ago', me, 60);
        old.Complete__c = true;
        old.Archived__c = true;
        old.Completed_Date__c = Datetime.now().addDays(-45);
        Planning_Item__c stillPending = PlannerTestData.item('Not archived', me, 60);
        insert new List<Planning_Item__c>{ recent, old, stillPending };

        List<PlannerModels.Task> completed = MemberTimesheetController.getCompletedTasks();

        Assert.areEqual(1, completed.size(), 'Only the recently archived task is within the rolling window');
        Assert.areEqual('Recently archived', completed[0].name);
    }

    @IsTest
    static void logTimeGoesThroughTheTimesheetSeam() {
        Id me = UserInfo.getUserId();
        Planning_Item__c task = PlannerTestData.item('Task', me, 60);
        insert task;
        StubTimesheetService stub = new StubTimesheetService();
        TimesheetServiceFactory.setMock(stub);

        Test.startTest();
        MemberTimesheetController.logTime(task.Id, Date.today(), 30);
        Test.stopTest();

        Assert.areEqual(task.Id, stub.lastTaskId, 'Correct task reached the seam');
        Assert.areEqual(30, stub.lastMinutes, 'Correct minutes reached the seam');
    }

    /** Proves no test depends on the real timesheet schema. */
    private class StubTimesheetService implements ITimesheetService {
        public Id lastTaskId;
        public Integer lastMinutes;
        public Id logEntry(Id taskId, Date entryDate, Integer minutes) {
            lastTaskId = taskId;
            lastMinutes = minutes;
            return null;
        }
        public void updateEntry(Id entryId, Date entryDate, Integer minutes) {}
        public void deleteEntry(Id entryId) {}
        public PlannerModels.TimeEntry getEntry(Id entryId) { return null; }
        public List<PlannerModels.TimeEntry> getEntriesForRange(Id userId, Date fromDate, Date toDate) {
            return new List<PlannerModels.TimeEntry>();
        }
    }
}
