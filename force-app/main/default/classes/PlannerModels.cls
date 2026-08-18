/**
 * Data transfer objects shared between the Apex layer and the LWC.
 * Deliberately plain: no SOQL, no DML, no dependency on the timesheet schema.
 */
public with sharing class PlannerModels {

    public class TimeEntry {
        @AuraEnabled public Id entryId;
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskName;
        @AuraEnabled public Date entryDate;
        @AuraEnabled public Integer minutes;
    }

    public class Task {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer estimateMinutes;
        @AuraEnabled public Integer loggedMinutes;
        @AuraEnabled public Integer remainingMinutes;
        @AuraEnabled public Boolean complete;
        @AuraEnabled public Boolean memberCreated;
        @AuraEnabled public Datetime completedDate;
    }

    public class Day {
        @AuraEnabled public Date theDate;
        @AuraEnabled public String weekdayName;
        @AuraEnabled public Boolean isFuture;
        @AuraEnabled public Boolean isToday;
        @AuraEnabled public Integer totalMinutes;
        @AuraEnabled public List<TimeEntry> entries;

        public Day() {
            this.entries = new List<TimeEntry>();
            this.totalMinutes = 0;
        }
    }

    public class Week {
        @AuraEnabled public Date weekStart;
        @AuraEnabled public Boolean isCurrentWeek;
        @AuraEnabled public List<Day> days;
        @AuraEnabled public List<Task> pending;

        public Week() {
            this.days = new List<Day>();
            this.pending = new List<Task>();
        }
    }
}
