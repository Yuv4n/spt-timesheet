/**
 * The board payload in one round trip.
 *
 * Lightning Data Service is record-at-a-time and cannot serve a board-shaped
 * response, so this is deliberate imperative Apex rather than @wire to LDS.
 */
public with sharing class PlannerBoardController {

    @AuraEnabled(cacheable=true)
    public static PlannerModels.Board getWeek(Date weekStart, List<Id> userIds) {
        try {
            if (weekStart == null) {
                weekStart = mondayOf(Date.today());
            }
            PlannerModels.Board board = new PlannerModels.Board();
            if (userIds == null || userIds.isEmpty()) {
                // Nothing selected yet (fresh App Builder page). Return an empty
                // board rather than letting a null bind blow up the SOQL.
                board.weekStart = weekStart;
                for (Integer i = 0; i < 5; i++) {
                    board.dates.add(weekStart.addDays(i));
                }
                return board;
            }
            board.weekStart = weekStart;
            for (Integer i = 0; i < 5; i++) {
                board.dates.add(weekStart.addDays(i));
            }

            List<User> users = [
                SELECT Id, Name
                FROM User
                WHERE Id IN :userIds AND IsActive = true
                WITH USER_MODE
                ORDER BY Name
            ];

            Map<Id, Map<String, Decimal>> capacityByUser = loadCapacity(userIds);
            Date weekEnd = board.dates[4];
            Map<Id, Set<Date>> absencesByUser = loadAbsences(userIds, weekStart, weekEnd);

            // Two deliberate choices in this query:
            //  - Completed work scheduled INSIDE this week is included. Excluding
            //    it would remove its consumed hours from the day totals, so an
            //    overrun would stop pushing later work down the moment it was
            //    marked done.
            //  - Work scheduled for another week is excluded, so next week's plan
            //    does not leak into this week's projection. Unscheduled work has
            //    no date and is treated as backlog / not yet placed.
            // LIMIT is a guard, not a page size: a real org's open backlog can be
            // large and this method must never approach the row governor limit.
            List<Planning_Item__c> records = [
                SELECT Id, Name, Item_Type__c, Case__c, Assignee__c, Estimate_Hours__c,
                       Actual_Minutes__c, Priority__c, Deadline__c, Status__c,
                       Scheduled_Date__c, Sequence__c, Pinned__c, Billable__c
                FROM Planning_Item__c
                WHERE (Assignee__c = null OR Assignee__c IN :userIds)
                  AND (
                        Scheduled_Date__c = null
                     OR (Scheduled_Date__c >= :weekStart AND Scheduled_Date__c <= :weekEnd)
                  )
                  AND (Status__c != 'Done' OR Scheduled_Date__c != null)
                WITH USER_MODE
                ORDER BY Sequence__c NULLS LAST, CreatedDate
                LIMIT 2000
            ];

            Map<Id, List<PlannerModels.Item>> itemsByUser = new Map<Id, List<PlannerModels.Item>>();
            List<PlannerModels.Item> allItems = new List<PlannerModels.Item>();
            for (Planning_Item__c rec : records) {
                PlannerModels.Item item = toDto(rec);
                allItems.add(item);
                if (item.assigneeId == null) {
                    board.backlog.add(item);
                } else {
                    if (!itemsByUser.containsKey(item.assigneeId)) {
                        itemsByUser.put(item.assigneeId, new List<PlannerModels.Item>());
                    }
                    itemsByUser.get(item.assigneeId).add(item);
                }
            }

            ScheduleProjector.flagBillability(allItems, findBillabilityProblems(allItems));

            for (User u : users) {
                PlannerModels.PersonWeek pw = new PlannerModels.PersonWeek();
                pw.userId = u.Id;
                pw.userName = u.Name;

                Map<Date, Decimal> capacity = buildCapacityMap(
                    board.dates,
                    capacityByUser.get(u.Id),
                    absencesByUser.containsKey(u.Id) ? absencesByUser.get(u.Id) : new Set<Date>()
                );

                List<PlannerModels.Item> mine = itemsByUser.containsKey(u.Id)
                    ? itemsByUser.get(u.Id)
                    : new List<PlannerModels.Item>();

                ScheduleProjector.Projection p = ScheduleProjector.project(mine, board.dates, capacity);
                pw.items = p.items;
                pw.days = p.days;
                board.people.add(pw);
            }
            return board;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the board: ' + e.getMessage());
        }
    }

    /**
     * Billability pre-flight. A case-linked item is at risk if its Case has no
     * Account or no Contact - that work gets done and cannot be invoiced.
     */
    private static Map<Id, String> findBillabilityProblems(List<PlannerModels.Item> items) {
        Set<Id> caseIds = new Set<Id>();
        for (PlannerModels.Item item : items) {
            if (item.caseId != null) {
                caseIds.add(item.caseId);
            }
        }
        Map<Id, String> problems = new Map<Id, String>();
        if (caseIds.isEmpty()) {
            return problems;
        }
        // WITH USER_MODE silently returns nothing if the running user cannot read
        // Case, which would report every item as safely billable. Track which
        // Cases came back so an unreadable one is flagged rather than assumed fine.
        Set<Id> seen = new Set<Id>();
        for (Case c : [SELECT Id, AccountId, ContactId FROM Case WHERE Id IN :caseIds WITH USER_MODE]) {
            seen.add(c.Id);
            if (c.AccountId == null && c.ContactId == null) {
                problems.put(c.Id, 'Case has no Account and no Contact');
            } else if (c.AccountId == null) {
                problems.put(c.Id, 'Case has no Account');
            } else if (c.ContactId == null) {
                problems.put(c.Id, 'Case has no Contact');
            }
        }
        for (Id caseId : caseIds) {
            if (!seen.contains(caseId)) {
                problems.put(caseId, 'Case could not be read - billability unverified');
            }
        }
        return problems;
    }

    /**
     * Re-sequence one person's whole week.
     *
     * Takes the person's COMPLETE ordered list, not one day's worth. Sequence is
     * global per person: numbering each day from zero would collide across days
     * and make the projector's ordering non-deterministic.
     *
     * Scheduled_Date__c is deliberately NOT written here. Dates for unpinned work
     * are computed by ScheduleProjector from sequence and capacity - they are a
     * result, not an input. Writing a date the projector then ignores would make
     * the board lie about what it is doing. Pinned items are the only work that
     * owns its date, and pinning is set on the record, not by dragging.
     */
    @AuraEnabled
    public static void reorder(List<Id> orderedItemIds, Id assigneeId) {
        if (orderedItemIds == null || orderedItemIds.isEmpty()) {
            return;
        }
        List<Planning_Item__c> updates = new List<Planning_Item__c>();
        Integer seq = 0;
        for (Id itemId : orderedItemIds) {
            updates.add(new Planning_Item__c(
                Id = itemId,
                Assignee__c = assigneeId,
                Sequence__c = seq++
            ));
        }
        try {
            update as user updates;
        } catch (Exception e) {
            throw new AuraHandledException('Could not save the new order: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void logActuals(Id itemId, Integer minutes) {
        try {
            List<Planning_Item__c> found = [
                SELECT Id, Case__c, Billable__c FROM Planning_Item__c
                WHERE Id = :itemId WITH USER_MODE LIMIT 1
            ];
            if (found.isEmpty()) {
                // Assigning an empty query straight to an sObject throws a bare
                // "List has no rows for assignment" - useless to the user.
                throw new AuraHandledException('That item no longer exists, or you do not have access to it.');
            }
            TimesheetServiceFactory.getInstance()
                .logActuals(itemId, minutes, found[0].Case__c, found[0].Billable__c);
        } catch (Exception e) {
            throw new AuraHandledException('Could not record time: ' + e.getMessage());
        }
    }

    // ---- helpers ----

    @TestVisible
    private static Date mondayOf(Date d) {
        Date reference = Date.newInstance(1900, 1, 1); // a Monday
        Integer offset = Math.mod(reference.daysBetween(d), 7);
        return d.addDays(-offset);
    }

    private static final List<String> WEEKDAY_NAMES = new List<String>{
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    };

    /**
     * Locale-independent weekday name.
     *
     * DateTime.format('EEEE') returns the name in the RUNNING USER'S locale, so a
     * user with a French or German locale gets 'lundi' / 'Montag', which never
     * matches the Capacity__c picklist and silently gives everyone zero hours.
     * This computes the offset from a known Monday instead.
     */
    @TestVisible
    private static String weekdayName(Date d) {
        Date reference = Date.newInstance(1900, 1, 1); // a Monday
        return WEEKDAY_NAMES[Math.mod(reference.daysBetween(d), 7)];
    }

    private static PlannerModels.Item toDto(Planning_Item__c rec) {
        PlannerModels.Item item = new PlannerModels.Item();
        item.itemId = rec.Id;
        item.name = rec.Name;
        item.itemType = rec.Item_Type__c;
        item.caseId = rec.Case__c;
        item.assigneeId = rec.Assignee__c;
        item.estimateHours = rec.Estimate_Hours__c;
        item.actualMinutes = rec.Actual_Minutes__c == null ? null : (Integer) rec.Actual_Minutes__c;
        item.priority = rec.Priority__c;
        item.deadline = rec.Deadline__c;
        item.status = rec.Status__c;
        item.scheduledDate = rec.Scheduled_Date__c;
        item.sequence = rec.Sequence__c == null ? null : (Integer) rec.Sequence__c;
        item.pinned = rec.Pinned__c;
        item.billable = rec.Billable__c;
        return item;
    }

    private static Map<Id, Map<String, Decimal>> loadCapacity(List<Id> userIds) {
        Map<Id, Map<String, Decimal>> result = new Map<Id, Map<String, Decimal>>();
        for (Capacity__c c : [
            SELECT User__c, Weekday__c, Available_Hours__c
            FROM Capacity__c WHERE User__c IN :userIds WITH USER_MODE
        ]) {
            if (!result.containsKey(c.User__c)) {
                result.put(c.User__c, new Map<String, Decimal>());
            }
            result.get(c.User__c).put(c.Weekday__c, c.Available_Hours__c);
        }
        return result;
    }

    private static Map<Id, Set<Date>> loadAbsences(List<Id> userIds, Date fromDate, Date toDate) {
        Map<Id, Set<Date>> result = new Map<Id, Set<Date>>();
        for (Absence__c a : [
            SELECT User__c, Start_Date__c, End_Date__c
            FROM Absence__c
            WHERE User__c IN :userIds AND End_Date__c >= :fromDate AND Start_Date__c <= :toDate
            WITH USER_MODE
        ]) {
            if (!result.containsKey(a.User__c)) {
                result.put(a.User__c, new Set<Date>());
            }
            // Clamp to the requested window. An absence record spanning years
            // would otherwise loop thousands of times per record.
            Date d = a.Start_Date__c < fromDate ? fromDate : a.Start_Date__c;
            Date last = a.End_Date__c > toDate ? toDate : a.End_Date__c;
            while (d <= last) {
                result.get(a.User__c).add(d);
                d = d.addDays(1);
            }
        }
        return result;
    }

    private static Map<Date, Decimal> buildCapacityMap(
        List<Date> dates, Map<String, Decimal> byWeekday, Set<Date> absent
    ) {
        Map<Date, Decimal> capacity = new Map<Date, Decimal>();
        for (Date d : dates) {
            if (absent.contains(d)) {
                capacity.put(d, 0);
                continue;
            }
            String weekday = weekdayName(d);
            Decimal hours = (byWeekday != null && byWeekday.containsKey(weekday))
                ? byWeekday.get(weekday)
                : 0;
            capacity.put(d, hours);
        }
        return capacity;
    }
}
