/**
 * Moves completed tasks out of the active pending list and into the
 * Completed section once the week they were finished in has passed
 * (decision 27/28). Manual trigger only for now (decision 32/33) - run via
 * scripts/apex/archive.apex.
 *
 * Only tasks completed BEFORE this week are archived - a task ticked earlier
 * this week must stay in the pending list regardless of when the script
 * happens to run (decision 27 is unconditional, not "until someone next runs
 * this script").
 */
public with sharing class TaskArchiver {

    public static Integer archiveCompletedTasks() {
        Date reference = Date.newInstance(1900, 1, 1); // a Monday
        Date today = Date.today();
        Date thisMonday = today.addDays(-Math.mod(reference.daysBetween(today), 7));

        List<Planning_Item__c> toArchive = [
            SELECT Id FROM Planning_Item__c
            WHERE Complete__c = true AND Archived__c = false AND Completed_Date__c < :thisMonday
            WITH USER_MODE
        ];
        for (Planning_Item__c t : toArchive) {
            t.Archived__c = true;
        }
        // Archived__c is not user-editable via FLS (system-managed), so this runs in
        // system context rather than `as user`.
        update toArchive;
        return toArchive.size();
    }
}
