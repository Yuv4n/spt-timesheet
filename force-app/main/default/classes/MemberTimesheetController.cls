/**
 * The member timesheet view in Apex: current/past week + pending list, time
 * logging, task lifecycle. Business rules that apply regardless of which
 * ITimesheetService implementation is plugged in (current-week-only edits,
 * duration limits, locking a complete task) live here, above the seam.
 */
public with sharing class MemberTimesheetController {

    @AuraEnabled(cacheable=true)
    public static PlannerModels.Week getWeek(Date weekStart) {
        try {
            Id me = UserInfo.getUserId();
            Date currentMonday = mondayOf(Date.today());
            Date monday = weekStart == null ? currentMonday : mondayOf(weekStart);
            if (monday > currentMonday) {
                throw new AuraHandledException('Cannot view a future week.');
            }

            PlannerModels.Week week = new PlannerModels.Week();
            week.weekStart = monday;
            week.isCurrentWeek = (monday == currentMonday);

            List<Date> dates = new List<Date>();
            for (Integer i = 0; i < 7; i++) {
                dates.add(monday.addDays(i));
            }
            Date sunday = dates[6];

            Map<Date, PlannerModels.Day> dayByDate = new Map<Date, PlannerModels.Day>();
            for (Date d : dates) {
                PlannerModels.Day day = new PlannerModels.Day();
                day.theDate = d;
                day.weekdayName = weekdayName(d);
                day.isFuture = d > Date.today();
                day.isToday = d == Date.today();
                dayByDate.put(d, day);
            }

            for (PlannerModels.TimeEntry e : TimesheetServiceFactory.getInstance().getEntriesForRange(me, monday, sunday)) {
                PlannerModels.Day day = dayByDate.get(e.entryDate);
                if (day != null) {
                    day.entries.add(e);
                    day.totalMinutes += e.minutes;
                }
            }
            for (Date d : dates) {
                week.days.add(dayByDate.get(d));
            }

            if (week.isCurrentWeek) {
                for (Planning_Item__c t : [
                    SELECT Id, Name, Estimate_Minutes__c, Total_Minutes_Logged__c,
                           Remaining_Minutes__c, Complete__c, Member_Created__c, Completed_Date__c
                    FROM Planning_Item__c
                    WHERE Assignee__c = :me AND Archived__c = false
                    WITH USER_MODE
                    ORDER BY Remaining_Minutes__c ASC NULLS LAST
                ]) {
                    week.pending.add(toTaskDto(t));
                }
            }

            return week;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load the week: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PlannerModels.Task> getCompletedTasks() {
        try {
            Id me = UserInfo.getUserId();
            Datetime cutoff = Datetime.now().addDays(-30);
            List<PlannerModels.Task> result = new List<PlannerModels.Task>();
            for (Planning_Item__c t : [
                SELECT Id, Name, Estimate_Minutes__c, Total_Minutes_Logged__c,
                       Remaining_Minutes__c, Complete__c, Member_Created__c, Completed_Date__c
                FROM Planning_Item__c
                WHERE Assignee__c = :me AND Archived__c = true AND Completed_Date__c >= :cutoff
                WITH USER_MODE
                ORDER BY Completed_Date__c DESC NULLS LAST
            ]) {
                result.add(toTaskDto(t));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load completed tasks: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id logTime(Id taskId, Date entryDate, Integer minutes) {
        try {
            Planning_Item__c t = ownedTask(taskId);
            assertNotComplete(t);
            assertWithinCurrentWeek(entryDate, 'log time');
            assertNotFuture(entryDate);
            assertMinutesValid(minutes);
            return TimesheetServiceFactory.getInstance().logEntry(taskId, entryDate, minutes);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not log time: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateTime(Id entryId, Date entryDate, Integer minutes) {
        try {
            PlannerModels.TimeEntry existing = TimesheetServiceFactory.getInstance().getEntry(entryId);
            if (existing == null) {
                throw new AuraHandledException('That entry no longer exists, or you do not have access to it.');
            }
            // No completeness check here - decision 19 grants an unconditional right to edit
            // entries within the current week; only NEW logging is locked by a complete task
            // (decision 25).
            ownedTask(existing.taskId);
            assertWithinCurrentWeek(existing.entryDate, 'edit entries');
            assertWithinCurrentWeek(entryDate, 'edit entries');
            assertNotFuture(entryDate);
            assertMinutesValid(minutes);
            TimesheetServiceFactory.getInstance().updateEntry(entryId, entryDate, minutes);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not update the entry: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteTime(Id entryId) {
        try {
            PlannerModels.TimeEntry existing = TimesheetServiceFactory.getInstance().getEntry(entryId);
            if (existing == null) {
                throw new AuraHandledException('That entry no longer exists, or you do not have access to it.');
            }
            // No completeness check here - decision 19 grants an unconditional right to delete
            // entries within the current week.
            ownedTask(existing.taskId);
            assertWithinCurrentWeek(existing.entryDate, 'delete entries');
            TimesheetServiceFactory.getInstance().deleteEntry(entryId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete the entry: ' + e.getMessage());
        }
    }

    /**
     * Complete__c and Completed_Date__c are not user-editable via FLS - completion only ever
     * happens through this method, so the stamp can never go missing, and this is the only path
     * that needs the object-level edit check below since it writes in system context.
     * Reopening also clears Archived__c: an archived-then-reopened task must return to the
     * pending list (decision 26), and it matches neither list while both flags disagree.
     */
    @AuraEnabled
    public static void setComplete(Id taskId, Boolean complete) {
        try {
            ownedTask(taskId);
            if (!Schema.sObjectType.Planning_Item__c.isUpdateable()) {
                throw new AuraHandledException('You do not have access to update tasks.');
            }
            Planning_Item__c toUpdate = new Planning_Item__c(
                Id = taskId,
                Complete__c = complete,
                Completed_Date__c = complete ? Datetime.now() : null
            );
            if (!complete) {
                toUpdate.Archived__c = false;
            }
            update toUpdate;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not update completion: ' + e.getMessage());
        }
    }

    /**
     * Assignee__c and Member_Created__c are not user-editable via FLS -
     * assignment is normally Raj's call, and Member_Created__c is a system
     * flag. Both are set here in system context after validating the inputs,
     * since this method is itself the one authorized path for self-assignment
     * at creation time.
     */
    @AuraEnabled
    public static Id createTask(String name, Integer estimateMinutes) {
        try {
            if (String.isBlank(name)) {
                throw new AuraHandledException('A task needs a name.');
            }
            if (estimateMinutes == null || estimateMinutes <= 0) {
                throw new AuraHandledException('A task needs an estimate.');
            }
            if (!Schema.sObjectType.Planning_Item__c.isCreateable()) {
                throw new AuraHandledException('You do not have access to create tasks.');
            }
            Planning_Item__c t = new Planning_Item__c(
                Name = name,
                Estimate_Minutes__c = estimateMinutes,
                Assignee__c = UserInfo.getUserId(),
                Member_Created__c = true,
                Status__c = 'Not Started'
            );
            insert t;
            return t.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not create the task: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void renameTask(Id taskId, String newName) {
        try {
            if (String.isBlank(newName)) {
                throw new AuraHandledException('A task needs a name.');
            }
            List<Planning_Item__c> found = [
                SELECT Id, Member_Created__c FROM Planning_Item__c
                WHERE Id = :taskId AND Assignee__c = :UserInfo.getUserId()
                WITH USER_MODE
                LIMIT 1
            ];
            if (found.isEmpty()) {
                throw new AuraHandledException('That task no longer exists, or you do not have access to it.');
            }
            if (!found[0].Member_Created__c) {
                throw new AuraHandledException('Only tasks you created yourself can be renamed.');
            }
            update as user new Planning_Item__c(Id = taskId, Name = newName);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not rename the task: ' + e.getMessage());
        }
    }

    // ---- helpers ----

    private static Planning_Item__c ownedTask(Id taskId) {
        List<Planning_Item__c> found = [
            SELECT Id, Complete__c FROM Planning_Item__c
            WHERE Id = :taskId AND Assignee__c = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('That task no longer exists, or you do not have access to it.');
        }
        return found[0];
    }

    private static void assertNotComplete(Planning_Item__c t) {
        if (t.Complete__c) {
            throw new AuraHandledException('This task is complete and read-only for time logging.');
        }
    }

    private static void assertWithinCurrentWeek(Date d, String verb) {
        Date monday = mondayOf(Date.today());
        Date sunday = monday.addDays(6);
        if (d == null || d < monday || d > sunday) {
            throw new AuraHandledException('You can only ' + verb + ' within the current week.');
        }
    }

    private static void assertNotFuture(Date d) {
        if (d > Date.today()) {
            throw new AuraHandledException('You cannot log time on a future day.');
        }
    }

    private static void assertMinutesValid(Integer minutes) {
        if (minutes == null || minutes < 15 || minutes > 720 || Math.mod(minutes, 15) != 0) {
            throw new AuraHandledException('Duration must be between 15 minutes and 12 hours, in 15-minute steps.');
        }
    }

    private static PlannerModels.Task toTaskDto(Planning_Item__c t) {
        PlannerModels.Task dto = new PlannerModels.Task();
        dto.taskId = t.Id;
        dto.name = t.Name;
        dto.estimateMinutes = t.Estimate_Minutes__c == null ? null : (Integer) t.Estimate_Minutes__c;
        dto.loggedMinutes = t.Total_Minutes_Logged__c == null ? 0 : (Integer) t.Total_Minutes_Logged__c;
        dto.remainingMinutes = t.Remaining_Minutes__c == null ? dto.estimateMinutes : (Integer) t.Remaining_Minutes__c;
        dto.complete = t.Complete__c;
        dto.memberCreated = t.Member_Created__c;
        dto.completedDate = t.Completed_Date__c;
        return dto;
    }

    /** Locale-independent Monday-of-week. DateTime.format('EEEE') uses the running user's locale. */
    @TestVisible
    private static Date mondayOf(Date d) {
        Date reference = Date.newInstance(1900, 1, 1); // a Monday
        Integer offset = Math.mod(reference.daysBetween(d), 7);
        return d.addDays(-offset);
    }

    private static final List<String> WEEKDAY_NAMES = new List<String>{
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    };

    @TestVisible
    private static String weekdayName(Date d) {
        Date reference = Date.newInstance(1900, 1, 1); // a Monday
        return WEEKDAY_NAMES[Math.mod(reference.daysBetween(d), 7)];
    }
}
