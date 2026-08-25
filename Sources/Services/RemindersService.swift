import EventKit
import Foundation
import SwiftUI

extension EKReminder: @retroactive Identifiable {
    public var id: String { calendarItemIdentifier }
}

@MainActor
class RemindersService: ObservableObject {
    private let store = EKEventStore()
    private var latestFetchToken = UUID()
    
    @Published var lists: [EKCalendar] = []
    @Published var reminders: [EKReminder] = []
    @Published var isAccessGranted: Bool = false
    
    // Simple caching/filtering
    @Published var activeListId: String? = nil // nil = Today/All
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        store.requestFullAccessToReminders { granted, error in
            Task { @MainActor in
                self.isAccessGranted = granted
                if granted {
                    self.fetchLists()
                    self.fetchReminders() 
                } else if let error = error {
                    AppLogger.reminders.error("Error requesting access: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    @Published var recentCompletedReminders: [EKReminder] = []

    // MARK: - All lists (grid + board)

    /// Every incomplete task, grouped by list identifier. The grid peeks into it
    /// and the board reads one list out of it.
    @Published var remindersByList: [String: [EKReminder]] = [:]

    private var allListsFetchToken = UUID()

    /// Flips to true the first time the grid or a board asks for all lists, and
    /// stays true for the launch. While it is set, every `fetchReminders()` also
    /// repopulates `remindersByList`, so no view has to remember to refresh —
    /// completing or dragging a task can never leave a stale board behind. The
    /// strip-only path (before the window is ever opened) stays exactly as cheap
    /// as it was.
    private var tracksAllLists = false

    func fetchLists() {
        let calendars = store.calendars(for: .reminder)
        self.lists = calendars
    }

    func reminders(in listId: String) -> [EKReminder] {
        remindersByList[listId] ?? []
    }

    /// One predicate across every calendar, grouped locally. Cheaper and far
    /// simpler than one fetch per list with a dispatch group, and it cannot
    /// half-complete.
    func fetchAllLists() {
        tracksAllLists = true
        fetchLists()

        let token = UUID()
        allListsFetchToken = token

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )

        store.fetchReminders(matching: predicate) { [weak self] fetched in
            guard let self, let fetched else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                var grouped: [String: [EKReminder]] = [:]
                for reminder in fetched {
                    guard let listId = reminder.calendar?.calendarIdentifier else { continue }
                    grouped[listId, default: []].append(reminder)
                }

                // Per-list key, the same one the strip already writes, so a task
                // never sits in a different place depending on which screen is
                // showing it.
                var sorted: [String: [EKReminder]] = [:]
                for (listId, reminders) in grouped {
                    sorted[listId] = Self.applySavedOrder(to: reminders, key: "sortOrder_\(listId)")
                }

                Task { @MainActor in
                    guard token == self.allListsFetchToken else { return }
                    self.remindersByList = sorted
                }
            }
        }
    }

    /// Creates a Reminders list in the store's default source.
    /// Returns nil when no source can hold one, so the caller can hide the
    /// affordance rather than fail on click.
    @discardableResult
    func createList(named title: String) -> EKCalendar? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let source = defaultReminderSource() else { return nil }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = trimmed
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
            fetchAllLists()
            return calendar
        } catch {
            AppLogger.reminders.error("Failed to create list: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// True when a new list can actually be created.
    var canCreateLists: Bool { defaultReminderSource() != nil }

    private func defaultReminderSource() -> EKSource? {
        store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { !$0.calendars(for: .reminder).isEmpty })
    }

    /// The saved-order comparator, shared by the single-list and all-lists
    /// fetches so a task never sits in a different place depending on which
    /// screen is showing it.
    private static func applySavedOrder(to reminders: [EKReminder], key: String) -> [EKReminder] {
        let savedOrder = UserDefaults.standard.stringArray(forKey: key) ?? []
        let idToIndex = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) })

        return reminders.sorted { r1, r2 in
            let i1 = idToIndex[r1.calendarItemIdentifier]
            let i2 = idToIndex[r2.calendarItemIdentifier]
            if let i1, let i2 { return i1 < i2 }
            if i1 != nil || i2 != nil {
                let a = i1 ?? Int.max
                let b = i2 ?? Int.max
                if a != b { return a < b }
            }
            return (r1.dueDateComponents?.date ?? Date.distantFuture)
                < (r2.dueDateComponents?.date ?? Date.distantFuture)
        }
    }
    
    func fetchReminders() {
        // Keep the board and the grid honest: they were populated once, so they
        // refresh with everything else rather than going stale behind a mutation.
        if tracksAllLists { fetchAllLists() }

        let fetchToken = UUID()
        latestFetchToken = fetchToken
        
        // Shared Date Logic
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        
        // Capture sort key on Main Thread (assuming fetchReminders is called from Main)
        let sortKey = self.currentSortOrderKey
        
        // 1. Fetch Incomplete Reminders
        let incompletePredicate: NSPredicate
        if activeListId == nil {
            // Today Mode: Incomplete due today or overdue
            incompletePredicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        } else {
            // Specific List: All incomplete in that list
            if let list = lists.first(where: { $0.calendarIdentifier == activeListId }) {
               incompletePredicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
            } else {
               // Fallback
               activeListId = nil
               fetchReminders()
               return
            }
        }
        
        store.fetchReminders(matching: incompletePredicate) { [weak self] reminders in
            guard let self = self, let reminders = reminders else { return }
            
            // Phase 2 Optimization: Async Sorting
            DispatchQueue.global(qos: .userInitiated).async {
                // Unified Sorting Strategy
                // Load saved order map once
                let savedOrder = UserDefaults.standard.stringArray(forKey: sortKey) ?? []
                let idToIndex = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) })
                
                let sortedReminders = reminders.sorted { (r1, r2) in
                    let idx1 = idToIndex[r1.calendarItemIdentifier]
                    let idx2 = idToIndex[r2.calendarItemIdentifier]
                    
                    // 1. Both have custom positions -> Sort by Index
                    if let i1 = idx1, let i2 = idx2 {
                        return i1 < i2
                    }
                    
                    // 2. Only one has custom position -> Custom one comes first? Or Last? 
                    // Let's replicate strict logic:
                    if idx1 != nil || idx2 != nil {
                        let i1 = idx1 ?? Int.max
                        let i2 = idx2 ?? Int.max
                        if i1 != i2 { return i1 < i2 }
                    }
                    
                    // 3. Fallback to Date (Due Date or Creation Date)
                    return (r1.dueDateComponents?.date ?? Date.distantFuture) < (r2.dueDateComponents?.date ?? Date.distantFuture)
                }
                
                Task { @MainActor in
                    guard fetchToken == self.latestFetchToken else { return }
                    self.reminders = sortedReminders
                }
            }
        }
        
        // 2. Fetch Recently Completed (Today)
        // ... (rest unchanged)
        let completedPredicate: NSPredicate
        let completionStart = startOfToday
        let completionEnd = endOfToday
        
        if activeListId == nil {
            completedPredicate = store.predicateForCompletedReminders(withCompletionDateStarting: completionStart, ending: completionEnd, calendars: nil)
        } else {
             if let list = lists.first(where: { $0.calendarIdentifier == activeListId }) {
                completedPredicate = store.predicateForCompletedReminders(withCompletionDateStarting: completionStart, ending: completionEnd, calendars: [list])
             } else {
                 return 
             }
        }
        
        store.fetchReminders(matching: completedPredicate) { [weak self] reminders in
            guard let self = self, let reminders = reminders else { return }
            
            // Async sort for completed as well
            DispatchQueue.global(qos: .userInitiated).async {
                let sortedCompleted = reminders.sorted {
                    ($0.completionDate ?? Date.distantPast) > ($1.completionDate ?? Date.distantPast)
                }
                Task { @MainActor in
                    guard fetchToken == self.latestFetchToken else { return }
                    self.recentCompletedReminders = sortedCompleted
                }
            }
        }
    }
    
    // ... (rest of methods)
    
    func toggleComplete(_ reminder: EKReminder) {
        do {
            reminder.isCompleted.toggle()
            try store.save(reminder, commit: true)
            // Ideally we animate it out, but for now just refresh
            fetchReminders()
        } catch {
            AppLogger.reminders.error("Failed to save reminder: \(String(describing: error), privacy: .public)")
        }
    }
    
    func updateTitle(_ reminder: EKReminder, newTitle: String) {
        guard reminder.title != newTitle else { return }
        reminder.title = newTitle
        do {
            try store.save(reminder, commit: true)
        } catch {
            AppLogger.reminders.error("Failed to update title: \(String(describing: error), privacy: .public)")
        }
    }
    
    func updateNotes(_ reminder: EKReminder, newNotes: String) {
        guard reminder.notes != newNotes else { return }
        reminder.notes = newNotes
        do {
            try store.save(reminder, commit: true)
            // No need to fetchReminders() if we are careful, but refreshing is safer for bindings
            objectWillChange.send() 
        } catch {
            AppLogger.reminders.error("Failed to update notes: \(String(describing: error), privacy: .public)")
        }
    }
    
    func updateDueDate(_ reminder: EKReminder, date: Date?) {
        let newComponents: DateComponents?
        if let date = date {
            newComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        } else {
            newComponents = nil
        }
        
        guard reminder.dueDateComponents != newComponents else { return }
        
        reminder.dueDateComponents = newComponents
        
        // Also update alarm if needed (optional but good for notifications)
        if let date = date {
            let alarm = EKAlarm(absoluteDate: date)
            reminder.alarms = [alarm]
        } else {
            reminder.alarms = []
        }
        
        do {
            try store.save(reminder, commit: true)
            fetchReminders() // Re-sort potentially
        } catch {
            AppLogger.reminders.error("Failed to update due date: \(String(describing: error), privacy: .public)")
        }
    }

    func dateComponents(from schedule: AssistantScheduleDraft?) -> DateComponents? {
        schedule?.resolvedDateComponents(calendar: .current)
    }

    func updateSchedule(_ reminder: EKReminder, schedule: AssistantScheduleDraft?) {
        let newComponents = dateComponents(from: schedule)
        guard reminder.dueDateComponents != newComponents else { return }

        reminder.dueDateComponents = newComponents

        if let absoluteDate = schedule?.resolvedDate(calendar: .current) {
            let alarm = EKAlarm(absoluteDate: absoluteDate)
            reminder.alarms = [alarm]
        } else {
            reminder.alarms = []
        }

        do {
            try store.save(reminder, commit: true)
            fetchReminders()
        } catch {
            AppLogger.reminders.error("Failed to update schedule: \(String(describing: error), privacy: .public)")
        }
    }
    
    func updatePriority(_ reminder: EKReminder, priority: Int) {
        // EKReminder priority: 0 (None), 1-4 (High), 5 (Medium), 6-9 (Low)
        // Standard mapping: High=1, Medium=5, Low=9, None=0
        guard reminder.priority != priority else { return }
        reminder.priority = priority
        do {
            try store.save(reminder, commit: true)
            fetchReminders() // Re-sort potentially if we sort by priority later
        } catch {
            AppLogger.reminders.error("Failed to update priority: \(String(describing: error), privacy: .public)")
        }
    }
    
    func updateRecurrence(_ reminder: EKReminder, frequency: EKRecurrenceFrequency?, interval: Int = 1) {
        if let frequency = frequency {
            let recurrenceRule = EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: interval,
                end: nil
            )
            reminder.recurrenceRules = [recurrenceRule]
        } else {
             reminder.recurrenceRules = nil
        }
        
        do {
            try store.save(reminder, commit: true)
            fetchReminders()
        } catch {
            AppLogger.reminders.error("Failed to update recurrence: \(String(describing: error), privacy: .public)")
        }
    }
    
    func createReminder(title: String, in calendar: EKCalendar? = nil, dueDate: DateComponents? = nil) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar ?? store.defaultCalendarForNewReminders()
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = dueDate
        }
        
        do {
            try store.save(reminder, commit: true)
            fetchReminders() // Fetch will handle appending to sort order
        } catch {
            AppLogger.reminders.error("Failed to create reminder: \(String(describing: error), privacy: .public)")
        }
    }

    func createReminder(from draft: TaskDraft, in calendar: EKCalendar? = nil) {
        createReminders(from: [draft], in: calendar)
    }

    func createReminders(from drafts: [TaskDraft], in calendar: EKCalendar? = nil) {
        let validDrafts = drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validDrafts.isEmpty else { return }

        for draft in validDrafts {
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.calendar = calendar ?? store.defaultCalendarForNewReminders()
            reminder.priority = draft.priority

            if let scheduleComponents = dateComponents(from: draft.schedule) {
                reminder.dueDateComponents = scheduleComponents
            }

            do {
                try store.save(reminder, commit: false)
            } catch {
                AppLogger.reminders.error("Failed to stage assistant reminder: \(String(describing: error), privacy: .public)")
            }
        }

        do {
            try store.commit()
            fetchReminders()
        } catch {
            AppLogger.reminders.error("Failed to commit assistant reminders: \(String(describing: error), privacy: .public)")
        }
    }

    func reminder(withId id: String) -> EKReminder? {
        if let reminder = reminders.first(where: { $0.calendarItemIdentifier == id }) {
            return reminder
        }
        return recentCompletedReminders.first(where: { $0.calendarItemIdentifier == id })
    }

    func buildAssistantContext() -> [AssistantReminderContext] {
        reminders.enumerated().map { index, reminder in
            AssistantReminderContext(
                id: reminder.calendarItemIdentifier,
                title: reminder.title,
                dueDate: reminder.dueDateComponents?.date,
                priority: reminder.priority,
                isCompleted: reminder.isCompleted,
                position: index + 1
            )
        }
    }

    func moveReminder(withId id: String, toPosition position: Int) {
        let zeroBasedDestination = max(position - 1, 0)
        moveReminder(withId: id, toIndex: min(zeroBasedDestination, reminders.count))
    }

    func applyAssistantAction(_ action: AssistantActionDraft, in calendar: EKCalendar? = nil) throws {
        switch action.kind {
        case .create:
            guard let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            createReminder(from: TaskDraft(title: title, schedule: action.schedule ?? .empty, priority: action.priority ?? 0), in: calendar)
        case .update:
            guard let targetId = action.targetReminderId,
                  let reminder = reminder(withId: targetId) else {
                throw AssistantError.actionTargetNotFound(action.targetReminderTitle ?? action.title ?? "Unknown")
            }
            if let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                updateTitle(reminder, newTitle: title)
            }
            if let schedule = action.schedule {
                updateSchedule(reminder, schedule: schedule)
            }
            if let priority = action.priority {
                updatePriority(reminder, priority: priority)
            }
        case .delete:
            guard let targetId = action.targetReminderId,
                  let reminder = reminder(withId: targetId) else {
                throw AssistantError.actionTargetNotFound(action.targetReminderTitle ?? "Unknown")
            }
            deleteReminder(reminder)
        case .complete:
            guard let targetId = action.targetReminderId,
                  let reminder = reminder(withId: targetId) else {
                throw AssistantError.actionTargetNotFound(action.targetReminderTitle ?? "Unknown")
            }
            let shouldBeCompleted = action.completed ?? true
            if reminder.isCompleted != shouldBeCompleted {
                toggleComplete(reminder)
            }
        case .reorder:
            guard let targetId = action.targetReminderId else {
                throw AssistantError.actionTargetNotFound(action.targetReminderTitle ?? "Unknown")
            }
            moveReminder(withId: targetId, toPosition: action.newPosition ?? 1)
        }
    }
    
    // MARK: - Sorting Logic
    
    private var currentSortOrderKey: String {
        return "sortOrder_\(activeListId ?? "today")"
    }
    
    private func saveSortOrder() {
        let ids = reminders.map { $0.calendarItemIdentifier }
        UserDefaults.standard.set(ids, forKey: currentSortOrderKey)
    }
    
    // Live Reordering Methods
    func moveInMemory(from source: IndexSet, to destination: Int) {
        // Safety check
        guard destination >= 0 && destination <= reminders.count else { return }
        reminders.move(fromOffsets: source, toOffset: destination)
    }
    
    func commitSortOrder() {
        saveSortOrder()
    }
    
    func moveReminder(from source: IndexSet, to destination: Int) {
        moveInMemory(from: source, to: destination)
        commitSortOrder()
    }
    
    // Helper for drag and drop single item (Legacy/Fallback)
    func moveReminder(withId id: String, toIndex index: Int) {
        guard let oldIndex = reminders.firstIndex(where: { $0.calendarItemIdentifier == id }) else { return }
        
        // Safety bounds
        guard index >= 0 && index <= reminders.count else { return }
        
        var newIndex = index
        if oldIndex < newIndex {
            newIndex -= 1 
        }
        
        if oldIndex == newIndex { return }
        
        var tempReminders = reminders
        
        // Safe removal
        if oldIndex < tempReminders.count {
            let item = tempReminders.remove(at: oldIndex)
            
            // Safe insertion
            if newIndex >= tempReminders.count {
                tempReminders.append(item)
            } else {
                tempReminders.insert(item, at: newIndex)
            }
            
            reminders = tempReminders
            saveSortOrder()
        }
    }
    
    func deleteReminder(_ reminder: EKReminder) {
        do {
            try store.remove(reminder, commit: true)
            fetchReminders()
        } catch {
            AppLogger.reminders.error("Failed to delete reminder: \(String(describing: error), privacy: .public)")
        }
    }
    
    func getNextTask(after currentId: String) -> EKReminder? {
        // Assuming 'reminders' is already sorted by priority/date
        if let index = reminders.firstIndex(where: { $0.calendarItemIdentifier == currentId }) {
            let nextIndex = index + 1
            if nextIndex < reminders.count {
                return reminders[nextIndex]
            }
        }
        // Fallback or loop if needed? For now just return nil if last.
        return nil
    }
}
