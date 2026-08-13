/**
 * Pure scheduling logic. No SOQL, no DML, no describe calls.
 *
 * Everything the spec calls "push-down" lives here and nowhere else, so it can
 * be unit tested exhaustively and explained in one sentence:
 *
 *   Walk a person's items in sequence order. Each item consumes its actual
 *   hours if recorded, otherwise its estimate. When a day runs out of capacity,
 *   the next item rolls to the following day. Pinned items never move.
 *
 * The projector never reassigns work between people and never reorders by
 * priority. Those are Raj's decisions, not the system's.
 */
public with sharing class ScheduleProjector {

    /**
     * @param items    Items for ONE person, already sorted by sequence.
     * @param dates    Ordered working dates in the week (typically Mon-Fri).
     * @param capacity Available hours keyed by date. Missing date = zero hours.
     * @return         The same items with projectedDate / risk flags populated,
     *                 plus per-day load totals.
     */
    public static Projection project(
        List<PlannerModels.Item> items,
        List<Date> dates,
        Map<Date, Decimal> capacity
    ) {
        Projection result = new Projection();

        Map<Date, PlannerModels.DayLoad> loadByDate = new Map<Date, PlannerModels.DayLoad>();
        Map<Date, Decimal> remaining = new Map<Date, Decimal>();
        for (Date d : dates) {
            Decimal cap = capacity.containsKey(d) ? capacity.get(d) : 0;
            loadByDate.put(d, new PlannerModels.DayLoad(d, cap));
            remaining.put(d, cap);
        }

        // Pinned items are placed first: they hold their date and consume from it.
        //
        // A pinned item whose date falls outside the displayed week is flagged
        // rather than quietly re-placed. Silently moving something the user
        // explicitly pinned is the one behaviour this class must never have.
        for (PlannerModels.Item item : items) {
            if (item.pinned != true) {
                continue;
            }
            if (item.scheduledDate != null && remaining.containsKey(item.scheduledDate)) {
                item.projectedDate = item.scheduledDate;
                consume(item, loadByDate, remaining);
            } else {
                item.pinnedOutsideWeek = true;
            }
        }

        Integer cursor = 0;
        for (PlannerModels.Item item : items) {
            if (item.pinned == true) {
                continue; // placed above, or flagged as outside the week
            }

            Decimal cost = item.consumedHours();

            // Advance past days that cannot take this item.
            //
            // A day with zero capacity (absence, non-working day) is ALWAYS
            // skipped - work is never scheduled onto a day someone is away.
            //
            // Otherwise a day accepts the item if it fits, or if the day is
            // still completely empty. The empty-day rule exists so that a
            // single item longer than a whole day is placed rather than
            // looping forever.
            while (cursor < dates.size()) {
                Date d = dates[cursor];
                Decimal cap = loadByDate.get(d).capacityHours;
                Decimal left = remaining.get(d);
                if (cap <= 0) {
                    cursor++;
                    continue;
                }
                Boolean dayUntouched = (left == cap);
                if (cost <= left || dayUntouched) {
                    break;
                }
                cursor++;
            }

            if (cursor >= dates.size()) {
                // Ran past the end of the week. Park it on the last WORKING day so
                // it is still visible, and flag it. Parking on a genuine calendar
                // last day that happens to be a zero-capacity absence day would
                // silently schedule work onto a day someone is away, which is the
                // one thing this class must never do.
                item.projectedDate = lastWorkingDay(dates, loadByDate);
                item.overflowsWeek = true;
            } else {
                item.projectedDate = dates[cursor];
                remaining.put(item.projectedDate, remaining.get(item.projectedDate) - cost);
            }

            if (item.projectedDate != null && loadByDate.containsKey(item.projectedDate)) {
                addHours(loadByDate.get(item.projectedDate), item);
            }

        }

        // Single risk pass, after every item (pinned included) has a date.
        for (PlannerModels.Item item : items) {
            evaluateRisk(item);
        }

        for (Date d : dates) {
            PlannerModels.DayLoad load = loadByDate.get(d);
            load.finalise();
            result.days.add(load);
        }
        result.items = items;
        return result;
    }

    /**
     * The last date in the week that can actually take work. Walks backwards
     * from the end of the week so overflow never lands on a zero-capacity
     * (absence) day just because it happens to be the final calendar date.
     */
    private static Date lastWorkingDay(List<Date> dates, Map<Date, PlannerModels.DayLoad> loadByDate) {
        if (dates.isEmpty()) {
            return null;
        }
        for (Integer i = dates.size() - 1; i >= 0; i--) {
            Date d = dates[i];
            if (loadByDate.get(d).capacityHours > 0) {
                return d;
            }
        }
        return dates[dates.size() - 1];
    }

    private static void consume(
        PlannerModels.Item item,
        Map<Date, PlannerModels.DayLoad> loadByDate,
        Map<Date, Decimal> remaining
    ) {
        Date d = item.projectedDate;
        remaining.put(d, remaining.get(d) - item.consumedHours());
        addHours(loadByDate.get(d), item);
    }

    private static void addHours(PlannerModels.DayLoad load, PlannerModels.Item item) {
        if (item.billable == true) {
            load.billableHours += item.consumedHours();
        } else {
            load.nonBillableHours += item.consumedHours();
        }
    }

    /**
     * Two independent risks:
     *  - deadline risk: projected completion lands after the deadline
     *  - billability risk: case-linked work that cannot be invoiced as it stands
     */
    private static void evaluateRisk(PlannerModels.Item item) {
        item.deadlineAtRisk =
            item.deadline != null &&
            item.projectedDate != null &&
            item.projectedDate > item.deadline;
    }

    /**
     * Billability pre-flight. Kept separate from project() because it needs Case
     * data the projector deliberately does not know about - the caller passes in
     * the set of Case Ids that are missing an Account or a Contact.
     */
    public static void flagBillability(
        List<PlannerModels.Item> items,
        Map<Id, String> caseIdToProblem
    ) {
        for (PlannerModels.Item item : items) {
            if (item.itemType != 'Case Linked') {
                continue;
            }
            if (item.caseId == null) {
                item.billabilityAtRisk = true;
                item.billabilityReason = 'Case-linked item has no Case';
            } else if (caseIdToProblem.containsKey(item.caseId)) {
                item.billabilityAtRisk = true;
                item.billabilityReason = caseIdToProblem.get(item.caseId);
            }
        }
    }

    public class Projection {
        public List<PlannerModels.Item> items = new List<PlannerModels.Item>();
        public List<PlannerModels.DayLoad> days = new List<PlannerModels.DayLoad>();
    }
}
