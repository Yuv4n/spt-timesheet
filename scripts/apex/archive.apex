/**
 * Archives completed tasks whose week has passed - moves them from the
 * pending list into the Completed section (decision 27/28). Manual trigger
 * only for now (decision 32/33). Run with:
 *   sf apex run --file scripts/apex/archive.apex --target-org vscodeOrg
 */
Integer archived = TaskArchiver.archiveCompletedTasks();
System.debug('Archived ' + archived + ' completed task(s).');
