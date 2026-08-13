/**
 * Diagnoses a blank board by testing the Apex layer on its own.
 *
 * Run with:
 *   sf apex run --file scripts/apex/diagnose.apex --target-org vscodeOrg
 *
 * Read the USER_DEBUG lines in the output. If Apex returns people and items
 * here, the problem is in the LWC. If it returns nothing, the problem is data
 * or permissions and the component is behaving correctly.
 */

Id me = UserInfo.getUserId();
System.debug('=== RUNNING AS: ' + me + ' ===');

// 1. Does the raw data exist at all?
System.debug('Planning items in org: ' + [SELECT COUNT() FROM Planning_Item__c]);
System.debug('Capacity records: ' + [SELECT COUNT() FROM Capacity__c]);
System.debug('Absences: ' + [SELECT COUNT() FROM Absence__c]);

// 2. Is any of it assigned to THIS user? A mismatch here is the usual cause:
//    the seed ran as one user, the page is configured with another Id.
System.debug('Items assigned to me: ' + [SELECT COUNT() FROM Planning_Item__c WHERE Assignee__c = :me]);
System.debug('Capacity rows for me: ' + [SELECT COUNT() FROM Capacity__c WHERE User__c = :me]);

for (Planning_Item__c p : [
    SELECT Name, Assignee__c, Assignee__r.Name, Scheduled_Date__c, Status__c
    FROM Planning_Item__c LIMIT 5
]) {
    System.debug('ITEM: ' + p.Name + ' | assignee=' + p.Assignee__r.Name
        + ' | date=' + p.Scheduled_Date__c + ' | status=' + p.Status__c);
}

// 3. Is the user active and visible? getWeek filters on IsActive = true.
for (User u : [SELECT Id, Name, IsActive FROM User WHERE Id = :me]) {
    System.debug('USER: ' + u.Name + ' active=' + u.IsActive);
}

// 4. Call the controller exactly as the LWC does.
PlannerModels.Board board = PlannerBoardController.getWeek(null, new List<Id>{ me });
System.debug('=== BOARD ===');
System.debug('weekStart: ' + board.weekStart);
System.debug('dates: ' + board.dates);
System.debug('people returned: ' + board.people.size());
System.debug('backlog size: ' + board.backlog.size());

for (PlannerModels.PersonWeek pw : board.people) {
    System.debug('PERSON: ' + pw.userName + ' items=' + pw.items.size());
    for (PlannerModels.DayLoad d : pw.days) {
        System.debug('   ' + d.theDate + ' capacity=' + d.capacityHours
            + ' scheduled=' + d.scheduledHours + ' over=' + d.overCapacity);
    }
    for (PlannerModels.Item i : pw.items) {
        System.debug('   ITEM ' + i.name + ' -> ' + i.projectedDate
            + ' deadlineRisk=' + i.deadlineAtRisk
            + ' billingRisk=' + i.billabilityAtRisk);
    }
}

if (board.people.isEmpty()) {
    System.debug('*** NO PEOPLE RETURNED. The User Id passed in did not match an active user. ***');
}
