import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getWeek from '@salesforce/apex/MemberTimesheetController.getWeek';
import getCompletedTasks from '@salesforce/apex/MemberTimesheetController.getCompletedTasks';
import logTime from '@salesforce/apex/MemberTimesheetController.logTime';
import updateTime from '@salesforce/apex/MemberTimesheetController.updateTime';
import deleteTime from '@salesforce/apex/MemberTimesheetController.deleteTime';
import setComplete from '@salesforce/apex/MemberTimesheetController.setComplete';
import createTask from '@salesforce/apex/MemberTimesheetController.createTask';
import renameTask from '@salesforce/apex/MemberTimesheetController.renameTask';

function formatMinutesStatic(total) {
    const h = Math.floor(total / 60);
    const m = total % 60;
    if (h > 0) {
        return m > 0 ? `${h}h ${m}m` : `${h}h`;
    }
    return `${m}m`;
}

/** 15-minute increments, 15 min to 12 hours (decision 17). */
const DURATION_OPTIONS = [];
for (let m = 15; m <= 720; m += 15) {
    DURATION_OPTIONS.push({ label: formatMinutesStatic(m), value: String(m) });
}

/** Member timesheet: day tabs, pending list, time logging, complete/reopen, week navigation, completed section. */
export default class MemberTimesheet extends LightningElement {
    // Must be initialised: an undefined reactive `$` wire parameter suppresses
    // the wire call entirely.
    weekStart = null;

    week;
    error;
    loaded = false;
    selectedDate;

    durationOptions = DURATION_OPTIONS;
    logTaskId;
    logMinutes = '15';
    logging = false;

    editingEntryId;
    editEntryDate;
    editMinutes;

    completedTasks = [];
    showCompleted = false;

    showCreateForm = false;
    newTaskName = '';
    newTaskHours = '0';
    newTaskMinutes = '0';
    creatingTask = false;

    renamingTaskId;
    renameValue = '';

    wiredWeekResult;

    @wire(getWeek, { weekStart: '$weekStart' })
    wiredWeek(result) {
        this.wiredWeekResult = result;
        const { data, error } = result;
        if (data) {
            this.week = this.decorate(data);
            this.error = undefined;
            this.loaded = true;
            const stillValid = this.selectedDate && this.week.days.some((d) => d.theDate === this.selectedDate);
            if (!stillValid) {
                const today = this.week.days.find((d) => d.isToday);
                this.selectedDate = today ? today.theDate : this.week.days[0].theDate;
            }
        } else if (error) {
            this.error = error.body ? error.body.message : 'Could not load your timesheet';
            this.week = undefined;
            this.loaded = true;
        }
    }

    @wire(getCompletedTasks)
    wiredCompleted({ data }) {
        // Non-fatal if it errors - the completed section just stays empty; the main
        // week view is the page's primary job and must not be blocked by this.
        this.completedTasks = data ? data.map((t) => this.decorateTask(t)) : [];
    }

    get isLoading() {
        return !this.loaded;
    }

    get weekLabel() {
        if (!this.week) {
            return '';
        }
        const start = new Date(`${this.week.weekStart}T00:00:00`);
        return start.toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });
    }

    /** Members cannot navigate to future weeks (decision 36). */
    get isNextDisabled() {
        return !this.week || this.week.isCurrentWeek;
    }

    /**
     * Tab CSS depends on selectedDate, which changes after week.days is
     * decorated - recomputed fresh on every access (reactive to
     * selectedDate) rather than baked in once at wire time.
     */
    get tabbedDays() {
        if (!this.week) {
            return [];
        }
        return this.week.days.map((day) => ({
            ...day,
            tabClass: this.tabClass(day)
        }));
    }

    /** Entries carry per-row edit state, so this is a getter, not baked in at wire time. */
    get selectedDay() {
        if (!this.week) {
            return undefined;
        }
        const day = this.week.days.find((d) => d.theDate === this.selectedDate);
        if (!day) {
            return undefined;
        }
        return {
            ...day,
            entries: day.entries.map((e) => ({
                ...e,
                isEditing: e.entryId === this.editingEntryId
            }))
        };
    }

    get hasSelectedDayEntries() {
        return this.selectedDay && this.selectedDay.entries.length > 0;
    }

    get isFutureDay() {
        return this.selectedDay && this.selectedDay.isFuture;
    }

    get hasPending() {
        return this.week && this.week.isCurrentWeek && this.week.pending.length > 0;
    }

    get hasCompletedTasks() {
        return this.completedTasks && this.completedTasks.length > 0;
    }

    get taskOptions() {
        if (!this.week) {
            return [];
        }
        return this.week.pending.filter((t) => !t.complete).map((t) => ({ label: t.name, value: t.taskId }));
    }

    get hasTaskOptions() {
        return this.taskOptions.length > 0;
    }

    /** Pending rows carry per-row rename state, so this is a getter, not baked in at wire time. */
    get pendingTasks() {
        if (!this.week) {
            return [];
        }
        return this.week.pending.map((t) => ({
            ...t,
            isRenaming: t.taskId === this.renamingTaskId
        }));
    }

    get newTaskEstimateMinutes() {
        const h = Number(this.newTaskHours) || 0;
        const m = Number(this.newTaskMinutes) || 0;
        return h * 60 + m;
    }

    get createTaskDisabled() {
        return this.creatingTask || !this.newTaskName.trim() || this.newTaskEstimateMinutes <= 0;
    }

    get newTaskToggleLabel() {
        return this.showCreateForm ? 'Cancel' : '+ New task';
    }

    /** Entries can only be edited/deleted within the current week (decision 19). */
    get canEditEntries() {
        return this.week && this.week.isCurrentWeek;
    }

    get canLogOnSelectedDay() {
        return this.canEditEntries && this.selectedDay && !this.selectedDay.isFuture;
    }

    get logDisabled() {
        return this.logging || !this.logTaskId;
    }

    handleSelectDay(event) {
        this.selectedDate = event.currentTarget.dataset.date;
        this.editingEntryId = null;
    }

    handlePrevWeek() {
        if (!this.week) {
            return;
        }
        this.weekStart = this.addDays(this.week.weekStart, -7);
        this.editingEntryId = null;
        this.logTaskId = null;
        this.logMinutes = '15';
        this.loaded = false;
    }

    handleNextWeek() {
        if (!this.week || this.week.isCurrentWeek) {
            return;
        }
        this.weekStart = this.addDays(this.week.weekStart, 7);
        this.editingEntryId = null;
        this.logTaskId = null;
        this.logMinutes = '15';
        this.loaded = false;
    }

    handleLogTaskChange(event) {
        this.logTaskId = event.detail.value;
    }

    handleLogMinutesChange(event) {
        this.logMinutes = event.detail.value;
    }

    async handleLogSubmit() {
        if (!this.logTaskId || !this.selectedDate) {
            return;
        }
        this.logging = true;
        try {
            await logTime({
                taskId: this.logTaskId,
                entryDate: this.selectedDate,
                minutes: Number(this.logMinutes)
            });
            this.logTaskId = null;
            this.logMinutes = '15';
            this.notify('success', 'Time logged');
        } catch (e) {
            this.notify('error', this.messageOf(e, 'Could not log time'));
            return;
        } finally {
            this.logging = false;
        }
        this.safeRefresh();
    }

    handleStartEdit(event) {
        const entryId = event.currentTarget.dataset.entryId;
        const entry = this.selectedDay.entries.find((e) => e.entryId === entryId);
        this.editingEntryId = entryId;
        this.editEntryDate = entry ? entry.entryDate : this.selectedDate;
        this.editMinutes = entry ? String(entry.minutes) : '15';
    }

    handleCancelEdit() {
        this.editingEntryId = null;
    }

    handleEditMinutesChange(event) {
        this.editMinutes = event.detail.value;
    }

    async handleSaveEdit(event) {
        const entryId = event.currentTarget.dataset.entryId;
        try {
            await updateTime({ entryId, entryDate: this.editEntryDate, minutes: Number(this.editMinutes) });
            this.editingEntryId = null;
            this.notify('success', 'Entry updated');
        } catch (e) {
            this.notify('error', this.messageOf(e, 'Could not update the entry'));
            return;
        }
        this.safeRefresh();
    }

    async handleDeleteEntry(event) {
        const entryId = event.currentTarget.dataset.entryId;
        const confirmed = await LightningConfirm.open({
            message: 'Delete this time entry? This cannot be undone.',
            label: 'Delete entry'
        });
        if (!confirmed) {
            return;
        }
        try {
            await deleteTime({ entryId });
            this.notify('success', 'Entry deleted');
        } catch (e) {
            this.notify('error', this.messageOf(e, 'Could not delete the entry'));
            return;
        }
        this.safeRefresh();
    }

    async handleToggleComplete(event) {
        const taskId = event.currentTarget.dataset.taskId;
        const complete = event.target.checked;
        try {
            await setComplete({ taskId, complete });
            this.notify('success', complete ? 'Task marked complete' : 'Task reopened');
        } catch (e) {
            // Revert the checkbox's optimistic UI state on failure.
            event.target.checked = !complete;
            this.notify('error', this.messageOf(e, 'Could not update completion'));
            return;
        }
        this.safeRefresh();
    }

    handleToggleCompletedSection() {
        this.showCompleted = !this.showCompleted;
    }

    handleToggleCreateForm() {
        this.showCreateForm = !this.showCreateForm;
        if (!this.showCreateForm) {
            this.resetCreateForm();
        }
    }

    resetCreateForm() {
        this.newTaskName = '';
        this.newTaskHours = '0';
        this.newTaskMinutes = '0';
    }

    handleNewTaskNameChange(event) {
        this.newTaskName = event.detail.value;
    }

    handleNewTaskHoursChange(event) {
        this.newTaskHours = event.detail.value;
    }

    handleNewTaskMinutesChange(event) {
        this.newTaskMinutes = event.detail.value;
    }

    async handleCreateTaskSubmit() {
        if (this.createTaskDisabled) {
            return;
        }
        this.creatingTask = true;
        try {
            await createTask({ name: this.newTaskName.trim(), estimateMinutes: this.newTaskEstimateMinutes });
            this.notify('success', 'Task created');
            this.resetCreateForm();
            this.showCreateForm = false;
        } catch (e) {
            this.notify('error', this.messageOf(e, 'Could not create the task'));
            return;
        } finally {
            this.creatingTask = false;
        }
        this.safeRefresh();
    }

    handleStartRename(event) {
        const taskId = event.currentTarget.dataset.taskId;
        const task = this.week.pending.find((t) => t.taskId === taskId);
        this.renamingTaskId = taskId;
        this.renameValue = task ? task.name : '';
    }

    handleCancelRename() {
        this.renamingTaskId = null;
    }

    handleRenameValueChange(event) {
        this.renameValue = event.detail.value;
    }

    async handleSaveRename(event) {
        const taskId = event.currentTarget.dataset.taskId;
        if (!this.renameValue.trim()) {
            return;
        }
        try {
            await renameTask({ taskId, newName: this.renameValue.trim() });
            this.renamingTaskId = null;
            this.notify('success', 'Task renamed');
        } catch (e) {
            this.notify('error', this.messageOf(e, 'Could not rename the task'));
            return;
        }
        this.safeRefresh();
    }

    /** Refreshing after a successful mutation is best-effort - a refresh failure must never be
     *  reported as if the mutation itself failed. */
    async safeRefresh() {
        try {
            await refreshApex(this.wiredWeekResult);
        } catch (e) {
            this.notify('warning', 'Saved, but the view could not refresh. Reload the page to see the latest.');
        }
    }

    decorate(raw) {
        return {
            ...raw,
            days: raw.days.map((day) => ({
                ...day,
                key: day.theDate,
                label: this.dayLabel(day.theDate),
                totalLabel: this.formatMinutes(day.totalMinutes),
                entries: day.entries.map((e) => ({
                    ...e,
                    key: e.entryId,
                    minutesLabel: this.formatMinutes(e.minutes)
                }))
            })),
            pending: raw.pending.map((t) => this.decorateTask(t))
        };
    }

    decorateTask(t) {
        const isOverrun = t.remainingMinutes < 0;
        const classes = ['task'];
        if (isOverrun) {
            classes.push('task_overrun');
        }
        if (t.complete) {
            classes.push('task_complete');
        }
        return {
            ...t,
            key: t.taskId,
            estimateLabel: this.formatMinutes(t.estimateMinutes),
            loggedLabel: this.formatMinutes(t.loggedMinutes),
            remainingLabel: this.formatMinutes(t.remainingMinutes),
            completedDateLabel: t.completedDate ? this.formatDate(t.completedDate) : '',
            isOverrun,
            rowClass: classes.join(' ')
        };
    }

    tabClass(day) {
        let cls = 'day-tab';
        if (day.theDate === this.selectedDate) {
            cls += ' day-tab_selected';
        }
        if (day.isToday) {
            cls += ' day-tab_today';
        }
        if (day.isFuture) {
            cls += ' day-tab_future';
        }
        return cls;
    }

    dayLabel(isoDate) {
        const d = new Date(`${isoDate}T00:00:00`);
        return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric' });
    }

    formatDate(isoDateTime) {
        const d = new Date(isoDateTime);
        return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
    }

    addDays(isoDate, n) {
        const d = new Date(`${isoDate}T00:00:00`);
        d.setDate(d.getDate() + n);
        return d.toISOString().slice(0, 10);
    }

    /** LWC templates cannot evaluate expressions, so all display state is computed here. */
    formatMinutes(total) {
        if (total === null || total === undefined) {
            return '0m';
        }
        const negative = total < 0;
        const abs = Math.abs(total);
        const h = Math.floor(abs / 60);
        const m = abs % 60;
        const label = h > 0 ? `${h}h${m > 0 ? ' ' + m + 'm' : ''}` : `${m}m`;
        return negative ? `-${label}` : label;
    }

    messageOf(e, fallback) {
        return e && e.body && e.body.message ? e.body.message : fallback;
    }

    notify(variant, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: variant === 'error' ? 'Error' : 'Success',
                message,
                variant
            })
        );
    }
}
