@IsTest
private class PlannerBoardControllerTest {

    @IsTest
    static void mondayOfReturnsTheStartOfTheWeek() {
        Date wednesday = Date.newInstance(2026, 8, 19);
        Assert.areEqual(
            Date.newInstance(2026, 8, 17),
            PlannerBoardController.mondayOf(wednesday),
            'Wednesday resolves back to Monday'
        );
        Assert.areEqual(
            Date.newInstance(2026, 8, 17),
            PlannerBoardController.mondayOf(Date.newInstance(2026, 8, 17)),
            'Monday resolves to itself'
        );
    }

    @IsTest
    static void boardReturnsFiveDaysAndTheAssignedItems() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);
        insert new List<Planning_Item__c>{
            PlannerTestData.item('Task A', me, 3),
            PlannerTestData.item('Task B', me, 3)
        };

        Test.startTest();
        PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>{ me });
        Test.stopTest();

        Assert.areEqual(5, board.dates.size(), 'A working week is five days');
        Assert.areEqual(1, board.people.size(), 'One person requested');
        Assert.areEqual(2, board.people[0].items.size(), 'Both items are on the board');
        Assert.areEqual(5, board.people[0].days.size(), 'Day loads for every day');
    }

    @IsTest
    static void unassignedItemsLandInTheBacklog() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);
        insert PlannerTestData.item('Unassigned', null, 2);

        PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>{ me });

        Assert.areEqual(1, board.backlog.size(), 'Unassigned work goes to the backlog');
        Assert.isTrue(board.people[0].items.isEmpty(), 'Nothing assigned to the person');
    }

    @IsTest
    static void caseMissingAContactIsFlaggedBeforeTheWorkStarts() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);

        Case broken = PlannerTestData.caseMissingContact();
        Planning_Item__c item = PlannerTestData.item('Client work', me, 4);
        item.Item_Type__c = 'Case Linked';
        item.Case__c = broken.Id;
        item.Billable__c = true;
        insert item;

        PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>{ me });

        Assert.isTrue(
            board.people[0].items[0].billabilityAtRisk,
            'Work on a Case with no Contact is flagged at scheduling time'
        );
    }

    @IsTest
    static void completeCaseIsNotFlagged() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);

        Case good = PlannerTestData.billableCase();
        Planning_Item__c item = PlannerTestData.item('Client work', me, 4);
        item.Item_Type__c = 'Case Linked';
        item.Case__c = good.Id;
        item.Billable__c = true;
        insert item;

        PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>{ me });

        Assert.isFalse(board.people[0].items[0].billabilityAtRisk, 'A complete Case is billable');
    }

    @IsTest
    static void absenceZeroesThatDaysCapacity() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);
        Date monday = PlannerBoardController.mondayOf(Date.today());
        insert new Absence__c(Name = 'Leave', User__c = me, Start_Date__c = monday, End_Date__c = monday);

        PlannerModels.Board board = PlannerBoardController.getWeek(monday, new List<Id>{ me });

        Assert.areEqual(0, board.people[0].days[0].capacityHours, 'No capacity on an absence day');
        Assert.areEqual(0, board.people[0].days[0].scheduledHours, 'And no work placed on it');
    }

    @IsTest
    static void completedWorkStillCountsTowardsTheDay() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);
        Date monday = PlannerBoardController.mondayOf(Date.today());

        Planning_Item__c done = PlannerTestData.item('Finished', me, 2);
        done.Status__c = 'Done';
        done.Actual_Minutes__c = 240; // four hours actually spent
        done.Scheduled_Date__c = monday;
        insert done;

        PlannerModels.Board board = PlannerBoardController.getWeek(monday, new List<Id>{ me });

        Assert.areEqual(1, board.people[0].items.size(),
            'Completed work in this week stays on the board so its hours still count');
        Assert.areEqual(4, board.people[0].days[0].scheduledHours,
            'Actual hours, not the estimate, consume the day');
    }

    @IsTest
    static void reorderWritesSequencePositions() {
        Id me = UserInfo.getUserId();
        List<Planning_Item__c> items = new List<Planning_Item__c>{
            PlannerTestData.item('First', me, 1),
            PlannerTestData.item('Second', me, 1)
        };
        insert items;

        Test.startTest();
        PlannerBoardController.reorder(new List<Id>{ items[1].Id, items[0].Id }, me);
        Test.stopTest();

        Map<Id, Planning_Item__c> saved = new Map<Id, Planning_Item__c>([
            SELECT Id, Sequence__c, Scheduled_Date__c FROM Planning_Item__c
        ]);
        Assert.areEqual(0, saved.get(items[1].Id).Sequence__c, 'Second item moved to position 0');
        Assert.areEqual(1, saved.get(items[0].Id).Sequence__c, 'First item moved to position 1');
    }

    @IsTest
    static void reorderDoesNotWriteAScheduledDate() {
        Id me = UserInfo.getUserId();
        Planning_Item__c item = PlannerTestData.item('Task', me, 1);
        insert item;

        PlannerBoardController.reorder(new List<Id>{ item.Id }, me);

        Planning_Item__c saved = [SELECT Scheduled_Date__c FROM Planning_Item__c WHERE Id = :item.Id];
        Assert.isNull(saved.Scheduled_Date__c,
            'Dates for unpinned work are computed by the projector, never stored by a reorder');
    }

    @IsTest
    static void reorderWithNoIdsIsANoOp() {
        PlannerBoardController.reorder(new List<Id>(), UserInfo.getUserId());
        Assert.areEqual(0, [SELECT COUNT() FROM Planning_Item__c], 'Nothing created or changed');
    }

    @IsTest
    static void emptyUserListReturnsAnEmptyBoardNotAnError() {
        PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>());
        Assert.areEqual(5, board.dates.size(), 'Still a five day week');
        Assert.isTrue(board.people.isEmpty(), 'No people');
        Assert.isTrue(board.backlog.isEmpty(), 'No backlog');
    }

    @IsTest
    static void nullUserListReturnsAnEmptyBoardNotAnError() {
        PlannerModels.Board board = PlannerBoardController.getWeek(null, null);
        Assert.isTrue(board.people.isEmpty(), 'A null bind must not blow up the SOQL');
    }

    @IsTest
    static void weekdayNamesAreLocaleIndependent() {
        Assert.areEqual('Monday', PlannerBoardController.weekdayName(Date.newInstance(2026, 8, 17)), 'Mon');
        Assert.areEqual('Friday', PlannerBoardController.weekdayName(Date.newInstance(2026, 8, 21)), 'Fri');
        Assert.areEqual('Sunday', PlannerBoardController.weekdayName(Date.newInstance(2026, 8, 23)), 'Sun');
    }

    @IsTest
    static void workScheduledInAnotherWeekDoesNotLeakIn() {
        Id me = UserInfo.getUserId();
        insert PlannerTestData.fullWeekCapacity(me, 7);
        Date monday = PlannerBoardController.mondayOf(Date.today());

        Planning_Item__c nextWeek = PlannerTestData.item('Next week', me, 3);
        nextWeek.Scheduled_Date__c = monday.addDays(9);
        insert nextWeek;

        PlannerModels.Board board = PlannerBoardController.getWeek(monday, new List<Id>{ me });
        Assert.isTrue(board.people[0].items.isEmpty(),
            'Next week is planned separately and must not consume this week');
    }

    @IsTest
    static void logActualsOnAMissingItemGivesAUsefulError() {
        // Use a real Id from a deleted record rather than a fabricated one: a
        // hand-written Id may not match this object's key prefix in every org.
        Planning_Item__c item = PlannerTestData.item('Doomed', UserInfo.getUserId(), 1);
        insert item;
        Id deletedId = item.Id;
        delete item;

        try {
            PlannerBoardController.logActuals(deletedId, 30);
            Assert.fail('Should not succeed against a deleted item');
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage(), 'An error is surfaced, not a bare list-has-no-rows exception');
        }
    }

    @IsTest
    static void logActualsGoesThroughTheTimesheetSeam() {
        Id me = UserInfo.getUserId();
        Planning_Item__c item = PlannerTestData.item('Task', me, 2);
        insert item;

        StubTimesheetService stub = new StubTimesheetService();
        TimesheetServiceFactory.setMock(stub);

        Test.startTest();
        PlannerBoardController.logActuals(item.Id, 150);
        Test.stopTest();

        Assert.areEqual(150, stub.lastMinutes, 'Minutes reached the timesheet service');
        Assert.areEqual(item.Id, stub.lastItemId, 'Correct item');
    }

    /** Proves no test depends on the real timesheet schema. */
    private class StubTimesheetService implements ITimesheetService {
        public Id lastItemId;
        public Integer lastMinutes;
        public void logActuals(Id itemId, Integer minutes, Id caseId, Boolean billable) {
            lastItemId = itemId;
            lastMinutes = minutes;
        }
        public Map<Id, Integer> getLoggedMinutes(Set<Id> itemIds) {
            return new Map<Id, Integer>();
        }
    }
}
