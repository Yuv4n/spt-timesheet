@IsTest
private class TaskArchiverTest {

    @IsTest
    static void archivesTasksCompletedInAPastWeek() {
        Id me = UserInfo.getUserId();
        Planning_Item__c done = PlannerTestData.item('Done last week', me, 60);
        done.Complete__c = true;
        done.Completed_Date__c = Datetime.now().addDays(-14);
        insert done;

        Test.startTest();
        Integer count = TaskArchiver.archiveCompletedTasks();
        Test.stopTest();

        Assert.areEqual(1, count, 'One task archived');
        Assert.isTrue([SELECT Archived__c FROM Planning_Item__c WHERE Id = :done.Id].Archived__c, 'Task is now archived');
    }

    @IsTest
    static void doesNotArchiveATaskCompletedThisWeek() {
        Id me = UserInfo.getUserId();
        Planning_Item__c done = PlannerTestData.item('Done just now', me, 60);
        done.Complete__c = true;
        done.Completed_Date__c = Datetime.now();
        insert done;

        Integer count = TaskArchiver.archiveCompletedTasks();

        Assert.areEqual(0, count, 'This week\'s completions stay in the pending list regardless of when the script runs');
        Assert.isFalse([SELECT Archived__c FROM Planning_Item__c WHERE Id = :done.Id].Archived__c);
    }

    @IsTest
    static void incompleteTasksAreUntouched() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.item('Still going', me, 60);

        TaskArchiver.archiveCompletedTasks();

        Assert.isFalse([SELECT Archived__c FROM Planning_Item__c LIMIT 1].Archived__c, 'Incomplete work is untouched');
    }

    @IsTest
    static void alreadyArchivedTasksAreNotCountedAgain() {
        Id me = UserInfo.getUserId();
        Planning_Item__c t = PlannerTestData.item('Old', me, 60);
        t.Complete__c = true;
        t.Completed_Date__c = Datetime.now().addDays(-14);
        insert t;
        TaskArchiver.archiveCompletedTasks();

        Integer secondRun = TaskArchiver.archiveCompletedTasks();

        Assert.areEqual(0, secondRun, 'Nothing left to archive');
    }
}
