/**
 * Data transfer objects shared between the Apex layer and the LWC board.
 * Deliberately plain: no SOQL, no DML, no dependency on the timesheet schema.
 */
public with sharing class PlannerModels {

    public class Item {
        @AuraEnabled public Id itemId;
        @AuraEnabled public String name;
        @AuraEnabled public String itemType;        // 'Case Linked' | 'Internal'
        @AuraEnabled public Id caseId;
        @AuraEnabled public Id assigneeId;
        @AuraEnabled public Decimal estimateHours;
        @AuraEnabled public Integer actualMinutes;
        @AuraEnabled public String priority;
        @AuraEnabled public Date deadline;
        @AuraEnabled public String status;
        @AuraEnabled public Date scheduledDate;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public Boolean pinned;
        @AuraEnabled public Boolean billable;

        // Populated by ScheduleProjector, never persisted.
        @AuraEnabled public Date projectedDate;
        @AuraEnabled public Boolean deadlineAtRisk;
        @AuraEnabled public Boolean billabilityAtRisk;
        @AuraEnabled public String billabilityReason;
        @AuraEnabled public Boolean overflowsWeek;
        @AuraEnabled public Boolean pinnedOutsideWeek;

        public Item() {
            this.pinned = false;
            this.billable = false;
            this.deadlineAtRisk = false;
            this.billabilityAtRisk = false;
            this.overflowsWeek = false;
            this.pinnedOutsideWeek = false;
        }

        /** Hours this item consumes: actuals win once recorded, else the estimate. */
        public Decimal consumedHours() {
            if (actualMinutes != null) {
                return ((Decimal) actualMinutes) / 60;
            }
            return estimateHours == null ? 0 : estimateHours;
        }
    }

    public class DayLoad {
        @AuraEnabled public Date theDate;
        @AuraEnabled public Decimal capacityHours;
        @AuraEnabled public Decimal billableHours;
        @AuraEnabled public Decimal nonBillableHours;
        @AuraEnabled public Boolean overCapacity;
        @AuraEnabled public Decimal scheduledHours;
        @AuraEnabled public Decimal freeHours;

        public DayLoad(Date d, Decimal capacity) {
            this.theDate = d;
            this.capacityHours = capacity;
            this.billableHours = 0;
            this.nonBillableHours = 0;
            this.overCapacity = false;
            this.scheduledHours = 0;
            this.freeHours = capacity;
        }

        /** Called once by ScheduleProjector after all items are placed. */
        public void finalise() {
            this.scheduledHours = billableHours + nonBillableHours;
            Decimal free = capacityHours - scheduledHours;
            this.freeHours = free < 0 ? 0 : free;
            this.overCapacity = scheduledHours > capacityHours;
        }
    }

    public class PersonWeek {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public List<Item> items;
        @AuraEnabled public List<DayLoad> days;

        public PersonWeek() {
            this.items = new List<Item>();
            this.days = new List<DayLoad>();
        }
    }

    public class Board {
        @AuraEnabled public Date weekStart;
        @AuraEnabled public List<Date> dates;
        @AuraEnabled public List<PersonWeek> people;
        @AuraEnabled public List<Item> backlog;

        public Board() {
            this.dates = new List<Date>();
            this.people = new List<PersonWeek>();
            this.backlog = new List<Item>();
        }
    }
}
