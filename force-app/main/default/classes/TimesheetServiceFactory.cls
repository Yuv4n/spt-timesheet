/**
 * Single point at which the timesheet implementation is chosen.
 *
 * When the SPT schema is confirmed, change ONE line here. Tests can inject a
 * stub via setMock() so no test ever depends on the real timesheet schema.
 */
public with sharing class TimesheetServiceFactory {

    @TestVisible private static ITimesheetService mockInstance;

    public static ITimesheetService getInstance() {
        if (Test.isRunningTest() && mockInstance != null) {
            return mockInstance;
        }
        // <-- CHANGE THIS LINE when the sandbox schema is known.
        return new LocalTimesheetService();
    }

    @TestVisible
    private static void setMock(ITimesheetService mock) {
        mockInstance = mock;
    }
}
