/**
 * Seed data for the dev org. Run with:
 *   sf apex run --file scripts/apex/seed.apex --target-org spt-dev
 *
 * Deliberately includes BROKEN records - a Case with no Contact, a Case with
 * no Account, an overbooked day, an already-breached deadline. The billability
 * and at-risk features cannot be developed against clean data.
 *
 * Idempotent: wipes planning data first. Safe in a dev org. NEVER run in the
 * SPT sandbox or production.
 */

// ---- wipe ----
delete [SELECT Id FROM Planning_Item__c];
delete [SELECT Id FROM Capacity__c];
delete [SELECT Id FROM Absence__c];
delete [SELECT Id FROM Case WHERE Subject LIKE 'SEED%'];
delete [SELECT Id FROM Contact WHERE LastName LIKE 'Seed%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'SEED%'];

Id me = UserInfo.getUserId();

// ---- accounts, contacts, cases (including the broken ones) ----
List<Account> accounts = new List<Account>{
    new Account(Name = 'SEED Northwind Ltd'),
    new Account(Name = 'SEED Contoso plc')
};
insert accounts;

List<Contact> contacts = new List<Contact>{
    new Contact(FirstName = 'Ana', LastName = 'Seed One', AccountId = accounts[0].Id),
    new Contact(FirstName = 'Ben', LastName = 'Seed Two', AccountId = accounts[1].Id)
};
insert contacts;

List<Case> cases = new List<Case>{
    // billable: complete
    new Case(Subject = 'SEED Integration work', AccountId = accounts[0].Id, ContactId = contacts[0].Id),
    new Case(Subject = 'SEED Report build',      AccountId = accounts[1].Id, ContactId = contacts[1].Id),
    // BROKEN: account but no contact -> will not bill
    new Case(Subject = 'SEED Missing contact',   AccountId = accounts[0].Id),
    // BROKEN: contact but no account
    new Case(Subject = 'SEED Missing account',   ContactId = contacts[1].Id),
    // BROKEN: neither
    new Case(Subject = 'SEED Missing both')
};
insert cases;

// ---- capacity: 7 productive hours a day ----
List<Capacity__c> caps = new List<Capacity__c>();
for (String day : new List<String>{ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday' }) {
    caps.add(new Capacity__c(Name = day, User__c = me, Weekday__c = day, Available_Hours__c = 7));
}
insert caps;

// ---- this week ----
Date today = Date.today();
Date reference = Date.newInstance(1900, 1, 1); // a Monday
Date monday = today.addDays(-Math.mod(reference.daysBetween(today), 7));

// ---- absence: half a week off, to test zero-capacity days ----
insert new Absence__c(
    Name = 'SEED Leave', User__c = me,
    Start_Date__c = monday.addDays(3), End_Date__c = monday.addDays(4)
);

List<Planning_Item__c> items = new List<Planning_Item__c>();
Integer seq = 0;

// pinned meeting - must not move
items.add(new Planning_Item__c(
    Name = 'SEED Team standup', Item_Type__c = 'Internal', Assignee__c = me,
    Estimate_Hours__c = 0.5, Priority__c = 'P2', Status__c = 'Not Started',
    Scheduled_Date__c = monday, Sequence__c = seq++, Pinned__c = true, Billable__c = false
));

// billable, complete case
items.add(new Planning_Item__c(
    Name = 'SEED Build integration', Item_Type__c = 'Case Linked', Case__c = cases[0].Id,
    Assignee__c = me, Estimate_Hours__c = 6, Priority__c = 'P1', Status__c = 'Not Started',
    Deadline__c = monday.addDays(2), Sequence__c = seq++, Billable__c = true
));

// billable in intent, but the Case cannot be invoiced - the flag we want to see
items.add(new Planning_Item__c(
    Name = 'SEED Client fix (no contact)', Item_Type__c = 'Case Linked', Case__c = cases[2].Id,
    Assignee__c = me, Estimate_Hours__c = 4, Priority__c = 'P1', Status__c = 'Not Started',
    Sequence__c = seq++, Billable__c = true
));

// overrun already recorded: 8h actual against a 2h estimate, pushes everything after it
items.add(new Planning_Item__c(
    Name = 'SEED Overran badly', Item_Type__c = 'Case Linked', Case__c = cases[1].Id,
    Assignee__c = me, Estimate_Hours__c = 2, Actual_Minutes__c = 480,
    Priority__c = 'P2', Status__c = 'In Progress', Sequence__c = seq++, Billable__c = true
));

// deadline already in the past - should flag red immediately
items.add(new Planning_Item__c(
    Name = 'SEED Already late', Item_Type__c = 'Case Linked', Case__c = cases[1].Id,
    Assignee__c = me, Estimate_Hours__c = 3, Priority__c = 'P1', Status__c = 'Not Started',
    Deadline__c = monday.addDays(-3), Sequence__c = seq++, Billable__c = true
));

// enough work to overflow the week
for (Integer i = 0; i < 4; i++) {
    items.add(new Planning_Item__c(
        Name = 'SEED Filler ' + i, Item_Type__c = 'Internal', Assignee__c = me,
        Estimate_Hours__c = 6, Priority__c = 'P3', Status__c = 'Not Started',
        Sequence__c = seq++, Billable__c = false
    ));
}

// unassigned - lands in the backlog
items.add(new Planning_Item__c(
    Name = 'SEED Unassigned work', Item_Type__c = 'Case Linked', Case__c = cases[3].Id,
    Estimate_Hours__c = 2, Priority__c = 'P2', Status__c = 'Not Started', Billable__c = true
));

insert items;

System.debug('Seeded ' + items.size() + ' planning items for week beginning ' + monday);
