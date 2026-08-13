import { LightningElement, api, wire } from 'lwc';
import getWeek from '@salesforce/apex/PlannerBoardController.getWeek';

/**
 * Read-only week board. Slice one of the MVP, deliberately.
 *
 * No drag and drop yet: this exists to prove the data shape, the capacity
 * maths and the billability flags survive contact with a screen. Interaction
 * comes next, once the grid-vs-list decision is made.
 */
export default class PlannerBoard extends LightningElement {
    // Must be initialised: an undefined reactive `$` wire parameter suppresses
    // the wire call entirely, so a bare `@api weekStart;` never fires getWeek.
    @api weekStart = null;

    board;
    error;
    loaded = false;

    _userIds = '';
    userIdList = [];

    /**
     * Comma-separated User Ids. Set in App Builder until a team model exists.
     *
     * This is a setter rather than a plain @api field because a wire's reactive
     * `$parameter` must point at a real field on the component. A getter looks
     * like it should work but does not reliably re-trigger the wire, so the
     * derived array is assigned to a field here instead.
     */
    @api
    get userIds() {
        return this._userIds;
    }

    set userIds(value) {
        this._userIds = value || '';
        this.userIdList = this._userIds
            .split(',')
            .map((id) => id.trim())
            .filter((id) => id.length > 0);
    }

    @wire(getWeek, { weekStart: '$weekStart', userIds: '$userIdList' })
    wiredBoard({ data, error }) {
        if (data) {
            this.board = this.decorate(data);
            this.error = undefined;
            this.loaded = true;
        } else if (error) {
            this.error = error.body ? error.body.message : 'Could not load the board';
            this.board = undefined;
            this.loaded = true;
        }
    }

    get isLoading() {
        return !this.loaded;
    }

    /** LWC templates cannot evaluate expressions, so all display state is computed here. */
    /** A component that renders nothing is impossible to diagnose. */
    get isEmpty() {
        return this.board && this.board.people.length === 0;
    }

    get hasNoUsers() {
        return this.userIdList.length === 0;
    }

    get weekLabel() {
        if (!this.board || !this.board.weekStart) {
            return '';
        }
        const d = new Date(`${this.board.weekStart}T00:00:00`);
        return d.toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });
    }

    decorate(raw) {
        return {
            ...raw,
            people: raw.people.map((person) => ({
                ...person,
                days: person.days.map((day) => ({
                    ...day,
                    key: `${person.userId}-${day.theDate}`,
                    label: this.dayLabel(day.theDate),
                    capacityClass: day.overCapacity ? 'day day_over' : 'day',
                    ...this.meterStyles(day),
                    items: person.items
                        .filter((item) => item.projectedDate === day.theDate)
                        .map((item) => this.decorateItem(item))
                }))
            })),
            backlog: raw.backlog.map((item) => this.decorateItem(item)),
            hasBacklog: raw.backlog.length > 0
        };
    }

    decorateItem(item) {
        const flags = [];
        if (item.deadlineAtRisk) {
            flags.push({ key: `${item.itemId}-deadline`, label: 'Past deadline', variant: 'flag flag_deadline' });
        }
        if (item.billabilityAtRisk) {
            flags.push({
                key: `${item.itemId}-billing`,
                label: item.billabilityReason || 'Not billable',
                variant: 'flag flag_billing'
            });
        }
        if (item.pinnedOutsideWeek) {
            flags.push({
                key: `${item.itemId}-pin`,
                label: 'Pinned outside this week',
                variant: 'flag flag_overflow'
            });
        }
        if (item.overflowsWeek) {
            flags.push({ key: `${item.itemId}-overflow`, label: 'Beyond this week', variant: 'flag flag_overflow' });
        }
        return {
            ...item,
            key: item.itemId,
            hours: this.formatHours(item),
            flags,
            hasFlags: flags.length > 0,
            cardClass: item.pinned ? 'item item_pinned' : 'item'
        };
    }

    formatHours(item) {
        if (item.actualMinutes !== null && item.actualMinutes !== undefined) {
            return `${(item.actualMinutes / 60).toFixed(1)}h actual`;
        }
        return `${Number(item.estimateHours || 0).toFixed(1)}h est`;
    }

    meterStyles(day) {
        const scheduled = (day.billableHours || 0) + (day.nonBillableHours || 0);
        const capacity = day.capacityHours || 0;
        const scale = Math.max(capacity, scheduled);

        if (scale <= 0) {
            return { billableStyle: 'width:0%', nonBillableStyle: 'width:0%', showLimit: false };
        }
        return {
            billableStyle: `width:${((day.billableHours || 0) / scale) * 100}%`,
            nonBillableStyle: `width:${((day.nonBillableHours || 0) / scale) * 100}%`,
            limitStyle: `left:${(capacity / scale) * 100}%`,
            showLimit: capacity > 0 && scheduled > capacity
        };
    }

    dayLabel(isoDate) {
        const d = new Date(`${isoDate}T00:00:00`);
        return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric' });
    }
}
