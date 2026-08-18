/**
 * Seed data for the dev org. Run with:
 *   sf apex run --file scripts/apex/seed.apex --target-org vscodeOrg
 *
 * Idempotent: wipes existing tasks first (cascades to any Timesheet_Entry__c
 * via the Master-Detail relationship). Dev-org only. NEVER run in the SPT
 * sandbox or production.
 */

delete [SELECT Id FROM Planning_Item__c];

Id me = UserInfo.getUserId();

List<Planning_Item__c> tasks = new List<Planning_Item__c>{
    new Planning_Item__c(Name = 'Weekly status report', Assignee__c = me, Estimate_Minutes__c = 30, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Client onboarding call', Assignee__c = me, Estimate_Minutes__c = 60, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Code review - checkout flow', Assignee__c = me, Estimate_Minutes__c = 45, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Sprint planning', Assignee__c = me, Estimate_Minutes__c = 90, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Bug triage', Assignee__c = me, Estimate_Minutes__c = 60, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Draft API documentation', Assignee__c = me, Estimate_Minutes__c = 120, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Customer support rotation', Assignee__c = me, Estimate_Minutes__c = 240, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Database migration testing', Assignee__c = me, Estimate_Minutes__c = 180, Status__c = 'Not Started'),
    new Planning_Item__c(Name = '1:1 with manager', Assignee__c = me, Estimate_Minutes__c = 30, Status__c = 'Not Started'),
    new Planning_Item__c(Name = 'Refactor auth module', Assignee__c = me, Estimate_Minutes__c = 300, Status__c = 'Not Started')
};

insert tasks;

System.debug('Seeded ' + tasks.size() + ' tasks for ' + me);
