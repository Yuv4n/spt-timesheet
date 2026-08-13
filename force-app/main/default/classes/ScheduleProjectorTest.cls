/**
 * ScheduleProjector is where the real bugs will live, so it gets the real tests.
 * No SOQL, no DML, no data setup - the class is pure, so the tests are fast.
 */
@IsTest
private class ScheduleProjectorTest {

    private static final Date MON = Date.newInstance(2026, 8, 17);

    private static List<Date> week() {
        return new List<Date>{ MON, MON.addDays(1), MON.addDays(2), MON.addDays(3), MON.addDays(4) };
    }

    private static Map<Date, Decimal> flatCapacity(Decimal hours) {
        Map<Date, Decimal> m = new Map<Date, Decimal>();
        for (Date d : week()) {
            m.put(d, hours);
        }
        return m;
    }

    private static PlannerModels.Item item(String name, Decimal estimate) {
        PlannerModels.Item i = new PlannerModels.Item();
        i.name = name;
        i.estimateHours = estimate;
        i.itemType = 'Internal';
        return i;
    }

    @IsTest
    static void itemsFillOneDayThenRollToTheNext() {
        List<PlannerModels.Item> items = new List<PlannerModels.Item>{
            item('A', 4), item('B', 3), item('C', 2)
        };
        ScheduleProjector.Projection p = ScheduleProjector.project(items, week(), flatCapacity(7));
        Assert.areEqual(MON, p.items[0].projectedDate, 'A fits Monday');
        Assert.areEqual(MON, p.items[1].projectedDate, 'B exactly fills Monday');
        Assert.areEqual(MON.addDays(1), p.items[2].projectedDate, 'C rolls to Tuesday');
    }

    @IsTest
    static void anOversizedItemDoesNotLoopForever() {
        List<PlannerModels.Item> items = new List<PlannerModels.Item>{ item('Huge', 40) };
        ScheduleProjector.Projection p = ScheduleProjector.project(items, week(), flatCapacity(7));
        Assert.areEqual(MON, p.items[0].projectedDate, 'An empty day always accepts the item');
        Assert.isTrue(p.days[0].overCapacity, 'Monday should be flagged over capacity');
    }

    @IsTest
    static void actualsOverrideEstimates() {
        PlannerModels.Item a = item('A', 2);
        a.actualMinutes = 360; // 6 hours actual against a 2 hour estimate
        PlannerModels.Item b = item('B', 2);
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ a, b }, week(), flatCapacity(7)
        );
        Assert.areEqual(MON, p.items[0].projectedDate, 'A stays on Monday');
        Assert.areEqual(MON.addDays(1), p.items[1].projectedDate, 'B is pushed by the overrun');
    }

    @IsTest
    static void pinnedItemsDoNotMove() {
        PlannerModels.Item meeting = item('Standup', 1);
        meeting.pinned = true;
        meeting.scheduledDate = MON.addDays(2);

        PlannerModels.Item work = item('Work', 20);

        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ meeting, work }, week(), flatCapacity(7)
        );
        Assert.areEqual(MON.addDays(2), p.items[0].projectedDate, 'Pinned item holds its date');
    }

    @IsTest
    static void pinnedItemOutsideTheWeekIsFlaggedNotSilentlyMoved() {
        PlannerModels.Item meeting = item('Offsite', 4);
        meeting.pinned = true;
        meeting.scheduledDate = MON.addDays(30); // next month

        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ meeting }, week(), flatCapacity(7)
        );
        Assert.isTrue(p.items[0].pinnedOutsideWeek, 'Flagged');
        Assert.isNull(p.items[0].projectedDate, 'Never silently re-placed into this week');
        Assert.areEqual(0, p.days[0].scheduledHours, 'And its hours do not consume this week');
    }

    @IsTest
    static void pinnedItemWithNoDateIsFlagged() {
        PlannerModels.Item orphan = item('Pinned but undated', 2);
        orphan.pinned = true;

        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ orphan }, week(), flatCapacity(7)
        );
        Assert.isTrue(p.items[0].pinnedOutsideWeek, 'A pin with no date is a data problem, not a placement');
    }

    @IsTest
    static void deadlineBreachIsFlagged() {
        PlannerModels.Item a = item('A', 7);
        PlannerModels.Item b = item('B', 7);
        b.deadline = MON; // due Monday but will land Tuesday
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ a, b }, week(), flatCapacity(7)
        );
        Assert.isFalse(p.items[0].deadlineAtRisk, 'A is not at risk');
        Assert.isTrue(p.items[1].deadlineAtRisk, 'B lands after its deadline');
    }

    @IsTest
    static void noWorkIsScheduledOnAnAbsenceDay() {
        Map<Date, Decimal> capacity = flatCapacity(7);
        capacity.put(MON, 0); // absence
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ item('A', 3) }, week(), capacity
        );
        Assert.areEqual(MON.addDays(1), p.items[0].projectedDate,
            'A zero-capacity day is skipped entirely, not filled');
        Assert.isFalse(p.days[0].overCapacity, 'Monday holds no work at all');
        Assert.areEqual(0, p.days[0].scheduledHours, 'Nothing scheduled on the absence day');
    }

    @IsTest
    static void consecutiveAbsenceDaysAreAllSkipped() {
        Map<Date, Decimal> capacity = flatCapacity(7);
        capacity.put(MON, 0);
        capacity.put(MON.addDays(1), 0);
        capacity.put(MON.addDays(2), 0);
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ item('A', 3) }, week(), capacity
        );
        Assert.areEqual(MON.addDays(3), p.items[0].projectedDate, 'Lands on the first working day');
    }

    @IsTest
    static void aFullyUnavailableWeekOverflowsRatherThanLooping() {
        Map<Date, Decimal> capacity = flatCapacity(0);
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ item('A', 3) }, week(), capacity
        );
        Assert.isTrue(p.items[0].overflowsWeek, 'No capacity anywhere means the work does not fit');
    }

    @IsTest
    static void workBeyondTheWeekIsFlaggedNotSilentlyDropped() {
        List<PlannerModels.Item> items = new List<PlannerModels.Item>();
        for (Integer i = 0; i < 8; i++) {
            items.add(item('Item ' + i, 7));
        }
        ScheduleProjector.Projection p = ScheduleProjector.project(items, week(), flatCapacity(7));
        Assert.isTrue(p.items[7].overflowsWeek, 'The eighth full day of work overflows the week');
    }

    @IsTest
    static void overflowNeverParksOnAZeroCapacityDay() {
        Map<Date, Decimal> capacity = flatCapacity(7);
        capacity.put(MON.addDays(3), 0); // Thursday absence
        capacity.put(MON.addDays(4), 0); // Friday absence

        List<PlannerModels.Item> items = new List<PlannerModels.Item>();
        for (Integer i = 0; i < 6; i++) {
            items.add(item('Item ' + i, 7));
        }
        ScheduleProjector.Projection p = ScheduleProjector.project(items, week(), capacity);

        Assert.areEqual(0, p.days[3].scheduledHours, 'Thursday is an absence day and must stay empty');
        Assert.areEqual(0, p.days[4].scheduledHours, 'Friday is an absence day and must stay empty');
        Assert.isTrue(p.items[5].overflowsWeek, 'The sixth full day of work overflows the week');
        Assert.areEqual(MON.addDays(2), p.items[5].projectedDate,
            'Overflow parks on Wednesday, the last day with capacity - not on a zero-capacity day');
    }

    @IsTest
    static void billableAndNonBillableHoursAreSplit() {
        PlannerModels.Item billableItem = item('Client work', 4);
        billableItem.billable = true;
        PlannerModels.Item internalItem = item('Team meeting', 2);

        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>{ billableItem, internalItem }, week(), flatCapacity(8)
        );
        Assert.areEqual(4, p.days[0].billableHours, 'Billable hours');
        Assert.areEqual(2, p.days[0].nonBillableHours, 'Non-billable hours');
        Assert.areEqual(2, p.days[0].freeHours, 'Remaining free hours');
        Assert.isFalse(p.days[0].overCapacity, 'Six of eight hours is not over capacity');
    }

    @IsTest
    static void caseLinkedItemWithoutAContactIsFlagged() {
        PlannerModels.Item a = item('Billable work', 2);
        a.itemType = 'Case Linked';
        a.caseId = '500000000000000AAA';

        PlannerModels.Item b = item('Internal work', 2);

        Map<Id, String> problems = new Map<Id, String>{
            '500000000000000AAA' => 'Case has no Contact'
        };
        ScheduleProjector.flagBillability(new List<PlannerModels.Item>{ a, b }, problems);

        Assert.isTrue(a.billabilityAtRisk, 'Case-linked item with an incomplete Case is at risk');
        Assert.areEqual('Case has no Contact', a.billabilityReason, 'Reason is surfaced to the user');
        Assert.isFalse(b.billabilityAtRisk, 'Internal work is never a billability risk');
    }

    @IsTest
    static void caseLinkedItemWithNoCaseAtAllIsFlagged() {
        PlannerModels.Item a = item('Orphan', 2);
        a.itemType = 'Case Linked';
        ScheduleProjector.flagBillability(new List<PlannerModels.Item>{ a }, new Map<Id, String>());
        Assert.isTrue(a.billabilityAtRisk, 'Case-linked with no Case is a data problem');
    }

    @IsTest
    static void emptyInputIsSafe() {
        ScheduleProjector.Projection p = ScheduleProjector.project(
            new List<PlannerModels.Item>(), week(), flatCapacity(7)
        );
        Assert.areEqual(5, p.days.size(), 'Days are returned even with no work');
        Assert.isTrue(p.items.isEmpty(), 'No items in, no items out');
    }
}
