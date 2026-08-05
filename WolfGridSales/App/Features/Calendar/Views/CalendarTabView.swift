import SwiftUI
import UIKit

struct CalendarTabView: View {
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var zoomNamespace

    @StateObject private var nowTicker = CalendarNowDisplayLink()
    @State private var level: CalendarLevel = .month
    @State private var selectedDate = Date()
    @State private var visibleDate = Date()
    @State private var monthMode: MonthDisplayMode = .details
    @State private var dayMode: DayDisplayMode = .singleDay
    @State private var items: [CalendarItem] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingAddSheet = false
    @State private var draftStartDate = Date()
    @State private var hourHeight: CGFloat = 56
    @State private var dayLayouts: [String: [CalendarTimedEventLayout]] = [:]
    @State private var selectedEditableItem: ActivityFeedItem?
    @State private var selectedCalendarEditableItem: CalendarEditableItem?
    @State private var selectedSessionDetail: CalendarSessionDetailItem?
    @State private var showItemOpenError = false
    @State private var appleCalendarAccessState: AppleCalendarAccessState = .notDetermined
    @State private var appleCalendarPullEnabled = false
    @State private var appleCalendarAlertMessage: String?

    private let calendar = FlyrCalendarDateHelpers.configuredCalendar()
    private let calendarRed = Color(red: 1, green: 0.23, blue: 0.19)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    searchStrip
                    content
                        .padding(.bottom, 12)
                }
                .padding(.top, max(proxy.safeAreaInsets.top - 2, 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            uiState.showTabBar = true
            if monthMode == .stacked || monthMode == .compact { monthMode = .details }
            if dayMode == .multiDay { dayMode = .singleDay }
            uiState.beginCalendarTabPresentation()
            nowTicker.start()
            Task {
                await refreshAppleCalendarState()
                await reloadItems()
            }
        }
        .onDisappear {
            nowTicker.stop()
            uiState.endCalendarTabPresentation()
        }
        .onChange(of: visibleDate) { _, _ in
            Task { await reloadItems() }
        }
        .onChange(of: items) { _, _ in
            Task { await refreshVisibleLayouts() }
        }
        .sheet(isPresented: $showingAddSheet) {
            CalendarEventEditorSheet(
                isPresented: $showingAddSheet,
                initialStart: draftStartDate
            ) { event in
                Task {
                    _ = try? await FlyrCalendarService.shared.createEvent(event)
                    await reloadItems()
                }
            }
        }
        .sheet(item: $selectedEditableItem) { item in
            ActivityFeedEditSheet(item: item) { title, address, dueDate, notes in
                try await ActivityFeedService.shared.saveEditedItem(
                    item,
                    title: title,
                    address: address,
                    dueDate: dueDate,
                    notes: notes
                )
                await reloadItems()
            }
            .presentationDetents([.height(430), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCalendarEditableItem) { editable in
            ActivityFeedEditSheet(item: editable.activityItem, requiresAddress: false) { title, address, dueDate, notes in
                _ = try await FlyrCalendarService.shared.updateEvent(
                    from: editable.calendarItem,
                    title: title,
                    location: address,
                    startAt: dueDate,
                    notes: notes
                )
                await reloadItems()
            }
            .presentationDetents([.height(430), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedSessionDetail) { item in
            NavigationStack {
                ActivitySessionDetailView(session: item.session)
            }
            .presentationDetents([.large])
        }
        .alert("Couldn’t open this calendar item.", isPresented: $showItemOpenError) {
            Button("OK", role: .cancel) {}
        }
        .alert("Apple Calendar", isPresented: Binding(
            get: { appleCalendarAlertMessage != nil },
            set: { if !$0 { appleCalendarAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appleCalendarAlertMessage ?? "")
        }
    }

    private var header: some View {
        if level == .day {
            return AnyView(dayTopHeader)
        }

        return AnyView(monthYearHeader)
    }

    private var monthYearHeader: some View {
        VStack(spacing: level == .month ? 14 : 8) {
            HStack(alignment: .center) {
                if level != .year {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            level = level == .day ? .month : .year
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: level == .month ? 22 : 20, weight: .semibold))
                            Text(backTitle)
                                .font(.system(size: level == .month ? 38 : 20, weight: level == .month ? .semibold : .regular))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, level == .month ? 2 : 13)
                        .frame(height: level == .month ? 52 : 42)
                        .contentShape(Rectangle())
                        .background {
                            if level != .month {
                                RoundedRectangle(cornerRadius: 21)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 0) {
                    ZStack {
                        Image(systemName: monthMode.symbol)
                            .font(.system(size: 18, weight: .regular))
                        CalendarViewMenuButton(
                            level: level,
                            monthMode: monthMode,
                            dayMode: dayMode,
                            setMonthMode: { mode in
                                monthMode = mode
                                level = .month
                            },
                            setDayMode: { mode in
                                dayMode = mode
                                level = .day
                            }
                        )
                    }
                    .frame(width: 48, height: 42)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            isSearching.toggle()
                            if !isSearching { searchText = "" }
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 25, weight: .regular))
                            .frame(width: 54, height: 42)
                    }
                    .buttonStyle(.plain)

                    appleCalendarButton

                    Button {
                        draftStartDate = defaultDraftStart
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .regular))
                            .frame(width: 48, height: 42)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.primary)
                .frame(height: 42)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 21))
            }
            .padding(.horizontal, 18)
            .padding(.top, 0)
            .padding(.bottom, level == .month ? 10 : 0)

            if level != .month {
                HStack {
                    Text(titleText)
                        .font(titleFont)
                        .fontWeight(level == .day ? .regular : .semibold)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var dayTopHeader: some View {
        HStack(alignment: .center) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    level = .month
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text(monthNameFormatter.string(from: selectedDate))
                        .font(.system(size: 20, weight: .regular))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 21))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 0) {
                ZStack {
                    Image(systemName: "list.bullet.below.rectangle")
                        .font(.system(size: 19, weight: .regular))
                    CalendarViewMenuButton(
                        level: level,
                        monthMode: monthMode,
                        dayMode: dayMode,
                        setMonthMode: { mode in
                            monthMode = mode
                            level = .month
                        },
                        setDayMode: { mode in
                            dayMode = mode
                            level = .day
                        }
                    )
                }
                .frame(width: 48, height: 42)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        isSearching.toggle()
                        if !isSearching { searchText = "" }
                    }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 25, weight: .regular))
                        .frame(width: 54, height: 42)
                }
                .buttonStyle(.plain)

                appleCalendarButton

                Button {
                    draftStartDate = defaultDraftStart
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .regular))
                        .frame(width: 48, height: 42)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.primary)
            .frame(height: 42)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 21))
        }
        .padding(.horizontal, 18)
        .padding(.top, 0)
        .padding(.bottom, 4)
        .background(Color(uiColor: .systemBackground))
    }

    private var searchStrip: some View {
        VStack(spacing: 0) {
            if isSearching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Cancel") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .foregroundColor(calendarRed)
                }
                .font(.system(size: 17))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var appleCalendarButton: some View {
        Button {
            Task { await toggleAppleCalendarPull() }
        } label: {
            Image(systemName: appleCalendarPullEnabled ? "calendar.badge.checkmark" : "calendar.badge.plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(appleCalendarPullEnabled ? calendarRed : .primary)
                .frame(width: 48, height: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appleCalendarPullEnabled ? "Stop showing Apple Calendar events" : "Show Apple Calendar events")
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            AgendaListView(
                items: filteredItems,
                selectedDate: selectedDate,
                query: searchText,
                calendar: calendar,
                calendarRed: calendarRed,
                onItemTap: openCalendarItem
            )
        } else {
            switch level {
            case .year:
                yearView
            case .month:
                monthView
            case .day:
                dayView
            }
        }
    }

    private var yearView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 22) {
                ForEach(monthsInVisibleYear, id: \.self) { month in
                    MiniMonthCard(
                        month: month,
                        items: itemsForMonth(month),
                        calendar: calendar,
                        red: calendarRed
                    )
                    .matchedGeometryEffect(id: "month-\(monthKey(month))", in: zoomNamespace)
                    .onTapGesture {
                        selectedDate = month
                        visibleDate = month
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            level = .month
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
        }
    }

    @ViewBuilder
    private var monthView: some View {
        if monthMode == .list {
            AgendaListView(items: items, selectedDate: selectedDate, query: "", calendar: calendar, calendarRed: calendarRed, onItemTap: openCalendarItem)
        } else {
            VStack(spacing: 0) {
                weekdayHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                MonthGridView(
                    month: visibleDate,
                    selectedDate: $selectedDate,
                    items: items,
                    mode: monthMode,
                    calendar: calendar,
                    red: calendarRed,
                    namespace: zoomNamespace,
                    onSelect: { date in
                        let isReselectingSelectedDay = calendar.isDate(date, inSameDayAs: selectedDate)
                        selectedDate = date
                        if isReselectingSelectedDay || monthMode == .compact {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                dayMode = .singleDay
                                level = .day
                            }
                        }
                    }
                )
                .gesture(monthSwipeGesture)

                if monthMode == .details {
                    Divider()
                    AgendaListView(
                        items: itemsStartingOnDay(selectedDate),
                        selectedDate: selectedDate,
                        query: "",
                        calendar: calendar,
                        calendarRed: calendarRed,
                        compact: true,
                        onItemTap: openCalendarItem
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var dayView: some View {
        if dayMode == .list {
            AgendaListView(items: itemsStartingOnDay(selectedDate), selectedDate: selectedDate, query: "", calendar: calendar, calendarRed: calendarRed, onItemTap: openCalendarItem)
        } else {
            DayTimelineView(
                selectedDate: selectedDate,
                items: items,
                layoutsByDay: dayLayouts,
                dayMode: dayMode,
                hourHeight: $hourHeight,
                now: nowTicker.now,
                calendar: calendar,
                calendarRed: calendarRed,
                onSelectDay: { date in
                    guard !calendar.isDate(date, inSameDayAs: selectedDate) else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        selectedDate = date
                        visibleDate = date
                    }
                    Task { await refreshVisibleLayouts() }
                },
                onSwipeDay: { delta in
                    guard dayMode == .singleDay,
                          let nextDate = calendar.date(byAdding: .day, value: delta, to: selectedDate) else {
                        return
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        selectedDate = nextDate
                        visibleDate = nextDate
                    }
                    Task { await refreshVisibleLayouts() }
                },
                onLongPressSlot: { date in
                    draftStartDate = date
                    showingAddSheet = true
                },
                onItemTap: openCalendarItem
            )
            .matchedGeometryEffect(id: "day-\(dayKey(selectedDate))", in: zoomNamespace)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 24)
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 44 else { return }
                let delta = value.translation.width < 0 ? 1 : -1
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    visibleDate = calendar.date(byAdding: .month, value: delta, to: visibleDate) ?? visibleDate
                    selectedDate = visibleDate
                }
            }
    }

    private var titleText: String {
        switch level {
        case .year:
            return yearFormatter.string(from: visibleDate)
        case .month:
            return monthNameFormatter.string(from: visibleDate)
        case .day:
            return dayTitleFormatter.string(from: selectedDate)
        }
    }

    private var titleFont: Font {
        switch level {
        case .year: return .system(size: 38, weight: .semibold)
        case .month: return .system(size: 36, weight: .semibold)
        case .day: return .system(size: 28, weight: .regular)
        }
    }

    private var backTitle: String {
        switch level {
        case .year: return ""
        case .month: return monthNameFormatter.string(from: visibleDate)
        case .day: return monthNameFormatter.string(from: selectedDate)
        }
    }

    private var defaultDraftStart: Date {
        let date = level == .day ? selectedDate : Date()
        let hour = calendar.component(.hour, from: Date())
        return calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: date) ?? date
    }

    private var filteredItems: [CalendarItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { $0.searchHaystack.contains(query) }
    }

    private var monthsInVisibleYear: [Date] {
        let start = FlyrCalendarDateHelpers.startOfYear(for: visibleDate, calendar: calendar)
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(1)) }
        let first = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[first...] + symbols[..<first])
    }

    private func reloadItems() async {
        await MainActor.run { isLoading = true }
        let range = FlyrCalendarDateHelpers.visibleRange(around: visibleDate, monthsBefore: 6, monthsAfter: 6, calendar: calendar)
        let nextItems = await FlyrCalendarService.shared.fetchCalendarItems(start: range.0, end: range.1)
        await MainActor.run {
            items = nextItems
            isLoading = false
        }
    }

    private func refreshAppleCalendarState() async {
        let enabled = await FlyrCalendarService.shared.isAppleCalendarPullEnabled()
        let state = await FlyrCalendarService.shared.appleCalendarAccessState()
        await MainActor.run {
            appleCalendarPullEnabled = enabled && state == .fullAccess
            appleCalendarAccessState = state
        }
        if enabled && state != .fullAccess {
            await FlyrCalendarService.shared.setAppleCalendarPullEnabled(false)
        }
    }

    private func toggleAppleCalendarPull() async {
        if appleCalendarPullEnabled {
            await FlyrCalendarService.shared.setAppleCalendarPullEnabled(false)
            await MainActor.run { appleCalendarPullEnabled = false }
            await reloadItems()
            return
        }

        let state = await FlyrCalendarService.shared.requestAppleCalendarPull()
        await MainActor.run {
            appleCalendarAccessState = state
            appleCalendarPullEnabled = state == .fullAccess
            appleCalendarAlertMessage = appleCalendarAccessMessage(for: state)
        }
        if state == .fullAccess {
            await reloadItems()
        }
    }

    private func appleCalendarAccessMessage(for state: AppleCalendarAccessState) -> String? {
        switch state {
        case .fullAccess:
            return "Apple Calendar events are now visible in WolfGrid."
        case .writeOnly:
            return "WolfGrid can add events to Apple Calendar, but needs full access to show existing iCloud events."
        case .denied:
            return "Calendar access is denied. Turn on Full Access for WolfGrid in Settings to show Apple Calendar events."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .notDetermined:
            return "WolfGrid needs full calendar access to show your Apple Calendar events."
        case .unavailable:
            return "Apple Calendar access is unavailable on this device."
        }
    }

    private func refreshVisibleLayouts() async {
        let days = dayMode == .multiDay ? multiDayDates : [selectedDate]
        var next: [String: [CalendarTimedEventLayout]] = [:]
        for day in days {
            let dayItems = itemsForDay(day)
            let layouts = await CalendarEventLayoutCache.shared.layouts(for: day, items: dayItems, calendar: calendar)
            next[dayKey(day)] = layouts
        }
        await MainActor.run { dayLayouts = next }
    }

    private func itemsForDay(_ date: Date) -> [CalendarItem] {
        let range = FlyrCalendarDateHelpers.dayRange(for: date, calendar: calendar)
        return items.filter { FlyrCalendarDateHelpers.intersects($0, start: range.0, end: range.1) }
    }

    private func itemsStartingOnDay(_ date: Date) -> [CalendarItem] {
        items
            .filter { calendar.isDate($0.startAt, inSameDayAs: date) }
            .sorted {
                if $0.startAt == $1.startAt { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return $0.startAt < $1.startAt
            }
    }

    private func itemsForMonth(_ date: Date) -> [CalendarItem] {
        let start = FlyrCalendarDateHelpers.startOfMonth(for: date, calendar: calendar)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return items.filter { FlyrCalendarDateHelpers.intersects($0, start: start, end: end) }
    }

    private func openCalendarItem(_ item: CalendarItem) {
        switch item.kind {
        case .session:
            openSessionItem(item)
        case .standalone:
            if let editableItem = activityFeedItem(from: item) {
                selectedCalendarEditableItem = CalendarEditableItem(calendarItem: item, activityItem: editableItem)
            } else {
                showItemOpenError = true
            }
        case .reminder, .meeting:
            if let editableItem = activityFeedItem(from: item), item.contactId != nil {
                selectedEditableItem = editableItem
            } else {
                showItemOpenError = true
            }
        case .appleCalendar:
            appleCalendarAlertMessage = "Apple Calendar events are read-only in WolfGrid."
        }
    }

    private func openSessionItem(_ item: CalendarItem) {
        let sessionId = item.sourceId
        Task {
            do {
                let session = try await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId)
                await MainActor.run {
                    guard let session else {
                        showItemOpenError = true
                        return
                    }
                    selectedSessionDetail = CalendarSessionDetailItem(id: sessionId, session: session)
                }
            } catch {
                await MainActor.run {
                    showItemOpenError = true
                }
            }
        }
    }

    private func activityFeedItem(from item: CalendarItem) -> ActivityFeedItem? {
        guard let kind = activityFeedKind(for: item) else {
            return nil
        }

        return ActivityFeedItem(
            id: "calendar-\(item.id)",
            title: normalized(item.contactName) ?? cleanCalendarTitle(item.title, kind: kind),
            subtitle: item.address ?? item.location ?? "",
            timestamp: item.startAt,
            dueDate: item.startAt,
            kind: kind,
            contactId: item.contactId,
            activityId: item.kind == .meeting ? item.sourceId : nil,
            address: item.address ?? item.location,
            notes: item.notes,
            sessionId: nil,
            sessionDurationSeconds: nil
        )
    }

    private func activityFeedKind(for item: CalendarItem) -> ActivityFeedKind? {
        if item.kind == .reminder { return .followUp }
        if item.kind == .meeting { return .appointment }

        switch FlyrCalendarEventType(rawValue: item.eventType) {
        case .followUp:
            return .followUp
        case .appointment:
            return .appointment
        default:
            return nil
        }
    }

    private func cleanCalendarTitle(_ title: String, kind: ActivityFeedKind) -> String {
        let prefixes: [String]
        switch kind {
        case .followUp:
            prefixes = ["Follow up: ", "Follow-Up: ", "Follow Up: "]
        case .appointment:
            prefixes = ["Appointment: "]
        case .session:
            prefixes = []
        }
        for prefix in prefixes where title.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
            return String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var multiDayDates: [Date] {
        (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedDate) }
    }

    private func monthKey(_ date: Date) -> String {
        monthKeyFormatter.string(from: date)
    }

    private func dayKey(_ date: Date) -> String {
        dayKeyFormatter.string(from: calendar.startOfDay(for: date))
    }

    private var monthTitleFormatter: DateFormatter { Self.monthTitleFormatter }
    private var monthNameFormatter: DateFormatter { Self.monthNameFormatter }
    private var yearFormatter: DateFormatter { Self.yearFormatter }
    private var dayTitleFormatter: DateFormatter { Self.dayTitleFormatter }
    private var monthKeyFormatter: DateFormatter { Self.monthKeyFormatter }
    private var dayKeyFormatter: DateFormatter { Self.dayKeyFormatter }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct MonthGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let items: [CalendarItem]
    let mode: MonthDisplayMode
    let calendar: Calendar
    let red: Color
    let namespace: Namespace.ID
    let onSelect: (Date) -> Void

    private var rowHeight: CGFloat { mode == .compact ? 56 : 48 }

    var body: some View {
        let days = FlyrCalendarDateHelpers.monthGrid(for: month, calendar: calendar)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(days) { cell in
                let dayItems = itemsForDay(cell.date)
                MonthDayCell(
                    date: cell.date,
                    isInDisplayedMonth: cell.isInDisplayedMonth,
                    isSelected: calendar.isDate(cell.date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(cell.date),
                    items: dayItems,
                    mode: mode,
                    calendar: calendar,
                    red: red
                )
                .matchedGeometryEffect(id: "day-\(dayKey(cell.date))", in: namespace)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(cell.date) }
            }
        }
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: month)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: mode)
    }

    private func itemsForDay(_ date: Date) -> [CalendarItem] {
        let range = FlyrCalendarDateHelpers.dayRange(for: date, calendar: calendar)
        return items.filter { FlyrCalendarDateHelpers.intersects($0, start: range.0, end: range.1) }
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: date))
    }
}

private struct MonthDayCell: View {
    let date: Date
    let isInDisplayedMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let items: [CalendarItem]
    let mode: MonthDisplayMode
    let calendar: Calendar
    let red: Color

    var body: some View {
        VStack(spacing: mode == .compact ? 3 : 2) {
            dayNumber
            monthMarkerRow
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel(accessibilityText)
    }

    private var dayNumber: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.system(size: mode == .compact ? 20 : 13, weight: .semibold))
            .foregroundColor(dayForeground)
            .frame(width: mode == .compact ? 30 : 22, height: mode == .compact ? 30 : 22)
            .background(dayBackground)
            .clipShape(Circle())
            .opacity(isInDisplayedMonth ? 1 : 0.38)
    }

    private var dotRow: some View {
        HStack(spacing: 3) {
            ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private var monthActivityGlyph: some View {
        if isInDisplayedMonth && shouldShowSessionStatus {
            Circle()
                .fill(hasSession ? Color(red: 0.2, green: 0.78, blue: 0.35) : red)
                .frame(width: mode == .compact ? 10 : 8, height: mode == .compact ? 10 : 8)
                .accessibilityHidden(true)
        } else if mode == .compact {
            dotRow
        }
    }

    private var monthMarkerRow: some View {
        HStack(spacing: 3) {
            monthActivityGlyph
            ForEach(monthMarkerLabels, id: \.self) { label in
                monthMarker(label)
            }
        }
        .frame(height: mode == .compact ? 16 : 20)
    }

    private func monthMarker(_ label: String) -> some View {
        Text(label)
            .font(.system(size: mode == .compact ? 8 : 7, weight: .bold))
            .foregroundColor(.black.opacity(0.78))
            .frame(width: markerWidth(for: label), height: mode == .compact ? 14 : 12)
            .background(CalendarColorKey.yellow.color)
            .clipShape(Capsule())
    }

    private func markerWidth(for label: String) -> CGFloat {
        label.contains("/") ? (mode == .compact ? 24 : 22) : (mode == .compact ? 14 : 12)
    }

    private var monthMarkerLabels: [String] {
        if hasAppointment && hasFollowUp { return ["A/F"] }
        if hasAppointment { return ["A"] }
        if hasFollowUp { return ["F"] }
        return []
    }

    private var dotColors: [Color] {
        return monthMarkerLabels.isEmpty ? [] : [CalendarColorKey.yellow.color]
    }

    private var hasAppointment: Bool {
        items.contains { FlyrCalendarEventType(rawValue: $0.eventType) == .appointment }
    }

    private var hasFollowUp: Bool {
        items.contains { FlyrCalendarEventType(rawValue: $0.eventType) == .followUp }
    }

    private var hasSession: Bool {
        items.contains { $0.kind == .session }
    }

    private var shouldShowSessionStatus: Bool {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        return day <= today
    }

    @ViewBuilder
    private var dayBackground: some View {
        if isToday {
            red
        } else if isSelected {
            Color(uiColor: .systemGray)
        } else {
            Color.clear
        }
    }

    private var dayForeground: Color {
        if isToday || isSelected { return .white }
        if !isInDisplayedMonth { return .secondary }
        return .primary
    }

    private var accessibilityText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let eventWord = items.count == 1 ? "event" : "events"
        return "\(formatter.string(from: date)), \(items.count) \(eventWord)"
    }
}

private struct MiniMonthCard: View {
    let month: Date
    let items: [CalendarItem]
    let calendar: Calendar
    let red: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 2) {
                ForEach(FlyrCalendarDateHelpers.monthGrid(for: month, calendar: calendar).prefix(35)) { cell in
                    Text("\(calendar.component(.day, from: cell.date))")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(calendar.isDateInToday(cell.date) ? .white : (cell.isInDisplayedMonth ? .primary : .secondary))
                        .frame(width: 14, height: 14)
                        .background(calendar.isDateInToday(cell.date) ? red : Color.clear)
                        .clipShape(Circle())
                        .opacity(cell.isInDisplayedMonth ? 1 : 0.25)
                }
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        return formatter.string(from: month)
    }
}

private struct DayTimelineView: View {
    let selectedDate: Date
    let items: [CalendarItem]
    let layoutsByDay: [String: [CalendarTimedEventLayout]]
    let dayMode: DayDisplayMode
    @Binding var hourHeight: CGFloat
    let now: Date
    let calendar: Calendar
    let calendarRed: Color
    let onSelectDay: (Date) -> Void
    let onSwipeDay: (Int) -> Void
    let onLongPressSlot: (Date) -> Void
    let onItemTap: (CalendarItem) -> Void

    @State private var pinchStartHourHeight: CGFloat?

    private let gutterWidth: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            weekStrip
            selectedDayTitleBar
            allDayStrip
            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            hourGrid(width: proxy.size.width)
                            ForEach(timelineDays, id: \.self) { day in
                                dayColumn(day: day, width: proxy.size.width)
                            }
                            nowLine(width: proxy.size.width)
                        }
                        .frame(height: hourHeight * 24)
                        .contentShape(Rectangle())
                        .overlay {
                            GeometryReader { timelineProxy in
                                TimelineGestureOverlay(
                                    onTap: { point in
                                        if let item = item(at: point, width: timelineProxy.size.width) {
                                            onItemTap(item)
                                        }
                                    },
                                    onLongPress: { point in
                                        guard let slot = TimelineSlotResolver.date(
                                            for: point,
                                            timelineWidth: timelineProxy.size.width,
                                            gutterWidth: gutterWidth,
                                            hourHeight: hourHeight,
                                            days: timelineDays,
                                            calendar: calendar
                                        ) else { return }
                                        onLongPressSlot(slot)
                                    },
                                    onPinchChanged: { scale in
                                        let baseline = pinchStartHourHeight ?? hourHeight
                                        if pinchStartHourHeight == nil {
                                            pinchStartHourHeight = baseline
                                        }
                                        hourHeight = min(88, max(28, baseline * scale))
                                    },
                                    onPinchEnded: {
                                        pinchStartHourHeight = nil
                                    }
                                )
                            }
                        }
                    }
                    .onAppear {
                        scrollProxy.scrollTo("hour-\(initialScrollHour)", anchor: .top)
                    }
                    .onChange(of: selectedDate) { _, _ in
                        scrollProxy.scrollTo("hour-\(initialScrollHour)", anchor: .top)
                    }
                }
            }
        }
        .simultaneousGesture(daySwipeGesture)
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard dayMode == .singleDay else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.35, abs(horizontal) > 52 else { return }
                onSwipeDay(horizontal < 0 ? 1 : -1)
            }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { day in
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(spacing: 4) {
                        Text(singleWeekdayFormatter.string(from: day))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(weekdayTextColor(day))
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : dateTextColor(day))
                            .frame(width: 36, height: 36)
                            .background(calendar.isDate(day, inSameDayAs: selectedDate) ? calendarRed : Color.clear)
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(weekStripAccessibilityLabel(for: day))
                .accessibilityAddTraits(calendar.isDate(day, inSameDayAs: selectedDate) ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectedDayTitleBar: some View {
        Text(selectedDayTitle)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var allDayStrip: some View {
        let allDayItems = items.filter { item in
            item.isAllDay && timelineDays.contains { day in
                let range = FlyrCalendarDateHelpers.dayRange(for: day, calendar: calendar)
                return FlyrCalendarDateHelpers.intersects(item, start: range.0, end: range.1)
            }
        }

        if !allDayItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allDayItems) { item in
                        Button {
                            onItemTap(item)
                        } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .frame(height: 22)
                                .background(CalendarColorKey.color(for: item.colorKey))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, gutterWidth)
            }
            .frame(height: 30)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func dateTextColor(_ day: Date) -> Color {
        if calendar.isDateInToday(day) {
            return calendarRed
        }
        if calendar.isDate(day, equalTo: selectedDate, toGranularity: .month) {
            return .primary
        }
        return .secondary
    }

    private func weekdayTextColor(_ day: Date) -> Color {
        if calendar.isDateInToday(day) {
            return calendarRed
        }
        return .secondary
    }

    private var selectedDayTitle: String {
        selectedDayTitleFormatter.string(from: selectedDate)
    }

    private var weekDates: [Date] {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: startOfDay) ?? startOfDay
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func weekStripAccessibilityLabel(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }

    private func hourLabelView(_ hour: Int) -> Text {
        if hour == 0 {
            return Text("")
        }
        if hour == 12 {
            return Text("Noon")
                .font(.system(size: 13, weight: .semibold))
        }
        let value = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return Text("\(value)")
            .font(.system(size: 18, weight: .regular))
            + Text(" \(suffix)")
            .font(.system(size: 10, weight: .semibold))
    }

    private func hourLabelOpacity(_ hour: Int) -> Double {
        hour == 0 ? 0 : 1
    }

    private var selectedDayTitleFormatter: DateFormatter {
        Self.selectedDayTitleFormatter
    }

    private var singleWeekdayFormatter: DateFormatter {
        Self.singleWeekdayFormatter
    }

    private var initialScrollHour: Int {
        if timelineDays.contains(where: { calendar.isDate($0, inSameDayAs: now) }) {
            return max(0, calendar.component(.hour, from: now) - 5)
        }
        return 8
    }

    private static let selectedDayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE – MMM d, yyyy"
        return formatter
    }()

    private static let singleWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private func hourGrid(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    hourLabelView(hour)
                        .foregroundColor(.secondary)
                        .opacity(hourLabelOpacity(hour))
                        .frame(width: gutterWidth - 10, alignment: .trailing)
                        .padding(.trailing, 10)
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.75))
                        .frame(height: 0.5)
                }
                .frame(width: width, height: hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    private func dayColumn(day: Date, width: CGFloat) -> some View {
        let dayWidth = max(1, (width - gutterWidth) / CGFloat(timelineDays.count))
        let dayIndex = timelineDays.firstIndex(of: day) ?? 0
        let xOrigin = gutterWidth + CGFloat(dayIndex) * dayWidth
        let layouts = layoutsByDay[dayKey(day)] ?? []
        return ZStack(alignment: .topLeading) {
            if dayMode == .multiDay && dayIndex > 0 {
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.5))
                    .frame(width: 0.5, height: hourHeight * 24)
            }
            ForEach(layouts) { layout in
                eventBlock(layout: layout, dayWidth: dayWidth)
            }
        }
        .frame(width: dayWidth, height: hourHeight * 24, alignment: .topLeading)
        .offset(x: xOrigin)
    }

    private func eventBlock(layout: CalendarTimedEventLayout, dayWidth: CGFloat) -> some View {
        let columnWidth = max(1, (dayWidth - 8) / CGFloat(layout.columnCount))
        let height = max(22, CGFloat(layout.durationMinutes) / 60 * hourHeight - 2)
        return VStack(alignment: .leading, spacing: 1) {
            Text(layout.item.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(timeRange(layout.item))
                .font(.system(size: 10, weight: .regular))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(width: columnWidth - 3, height: height, alignment: .topLeading)
        .background(CalendarColorKey.color(for: layout.item.colorKey).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .offset(
            x: 4 + CGFloat(layout.column) * columnWidth,
            y: CGFloat(layout.startMinute) / 60 * hourHeight
        )
    }

    private func item(at point: CGPoint, width: CGFloat) -> CalendarItem? {
        guard point.x >= gutterWidth, width > gutterWidth else { return nil }
        let days = timelineDays
        guard !days.isEmpty else { return nil }

        let dayWidth = max(1, (width - gutterWidth) / CGFloat(days.count))
        let rawDayIndex = Int((point.x - gutterWidth) / dayWidth)
        let dayIndex = min(days.count - 1, max(0, rawDayIndex))
        let localX = point.x - gutterWidth - CGFloat(dayIndex) * dayWidth
        let layouts = layoutsByDay[dayKey(days[dayIndex])] ?? []

        return layouts.first { layout in
            let columnWidth = max(1, (dayWidth - 8) / CGFloat(layout.columnCount))
            let x = 4 + CGFloat(layout.column) * columnWidth
            let y = CGFloat(layout.startMinute) / 60 * hourHeight
            let blockWidth = columnWidth - 3
            let blockHeight = max(22, CGFloat(layout.durationMinutes) / 60 * hourHeight - 2)
            return localX >= x && localX <= x + blockWidth && point.y >= y && point.y <= y + blockHeight
        }?.item
    }

    @ViewBuilder
    private func nowLine(width: CGFloat) -> some View {
        if timelineDays.contains(where: { calendar.isDate($0, inSameDayAs: now) }) {
            let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            HStack(spacing: 0) {
                Text(nowLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(calendarRed)
                    .clipShape(Capsule())
                    .frame(width: gutterWidth, alignment: .trailing)
                Circle()
                    .fill(calendarRed)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(calendarRed)
                    .frame(width: width - gutterWidth, height: 1)
            }
            .offset(y: CGFloat(minutes) / 60 * hourHeight - 10)
            .animation(.linear(duration: 0.25), value: now)
            .accessibilityLabel("Current time \(nowLabel)")
        }
    }

    private var timelineDays: [Date] {
        let count = dayMode == .multiDay ? 3 : 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: selectedDate)) }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "" }
        let value = hour % 12 == 0 ? 12 : hour % 12
        return "\(value) \(hour < 12 ? "AM" : "PM")"
    }

    private func timeRange(_ item: CalendarItem) -> String {
        "\(timeFormatter.string(from: item.startAt))-\(timeFormatter.string(from: item.endAt))"
    }

    private var nowLabel: String {
        timeFormatter.string(from: now)
    }

    private func dayKey(_ date: Date) -> String {
        dayKeyFormatter.string(from: calendar.startOfDay(for: date))
    }

    private var shortWeekdayFormatter: DateFormatter {
        Self.shortWeekdayFormatter
    }

    private var timeFormatter: DateFormatter {
        Self.timeFormatter
    }

    private var dayKeyFormatter: DateFormatter {
        Self.dayKeyFormatter
    }

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct TimelineSlotResolver {
    static func date(
        for point: CGPoint,
        timelineWidth: CGFloat,
        gutterWidth: CGFloat,
        hourHeight: CGFloat,
        days: [Date],
        calendar: Calendar,
        snapMinutes: Int = 15
    ) -> Date? {
        guard !days.isEmpty, timelineWidth > gutterWidth, hourHeight > 0, snapMinutes > 0 else {
            return nil
        }

        let x = max(gutterWidth, min(point.x, timelineWidth))
        let dayWidth = max(1, (timelineWidth - gutterWidth) / CGFloat(days.count))
        let rawDayIndex = Int((x - gutterWidth) / dayWidth)
        let dayIndex = min(days.count - 1, max(0, rawDayIndex))

        let rawMinutes = (max(0, point.y) / hourHeight) * 60
        let snappedMinutes = min(
            23 * 60 + (60 - snapMinutes),
            max(0, Int((rawMinutes / CGFloat(snapMinutes)).rounded()) * snapMinutes)
        )
        return calendar.date(byAdding: .minute, value: snappedMinutes, to: calendar.startOfDay(for: days[dayIndex]))
    }
}

private struct TimelineGestureOverlay: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void
    let onPinchChanged: (CGFloat) -> Void
    let onPinchEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(tapRecognizer)

        let longPressRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.45
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(longPressRecognizer)

        let pinchRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchRecognizer.cancelsTouchesInView = false
        pinchRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(pinchRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onPinchChanged = onPinchChanged
        context.coordinator.onPinchEnded = onPinchEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onLongPress: onLongPress,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void
        var onLongPress: (CGPoint) -> Void
        var onPinchChanged: (CGFloat) -> Void
        var onPinchEnded: () -> Void

        init(
            onTap: @escaping (CGPoint) -> Void,
            onLongPress: @escaping (CGPoint) -> Void,
            onPinchChanged: @escaping (CGFloat) -> Void,
            onPinchEnded: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            onTap(recognizer.location(in: view))
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            onLongPress(recognizer.location(in: view))
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onPinchChanged(recognizer.scale)
            case .ended, .cancelled, .failed:
                onPinchEnded()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct CalendarSessionDetailItem: Identifiable {
    let id: UUID
    let session: SessionRecord
}

private struct CalendarEditableItem: Identifiable {
    let calendarItem: CalendarItem
    let activityItem: ActivityFeedItem

    var id: String {
        calendarItem.id
    }
}

private struct AgendaListView: View {
    let items: [CalendarItem]
    let selectedDate: Date
    let query: String
    let calendar: Calendar
    let calendarRed: Color
    var compact: Bool = false
    let onItemTap: (CalendarItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: compact ? 10 : 16, pinnedViews: []) {
                if groupedItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 28, weight: .regular))
                        Text("No Events")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                } else {
                    ForEach(groupedItems, id: \.date) { section in
                        Text(sectionTitle(section.date))
                            .font(.system(size: compact ? 14 : 17, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 28)
                            .padding(.top, compact ? 6 : 12)

                        ForEach(section.items) { item in
                            Button {
                                onItemTap(item)
                            } label: {
                                AgendaRow(item: item, query: query, calendarRed: calendarRed)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 28)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var groupedItems: [(date: Date, items: [CalendarItem])] {
        if compact {
            return [(calendar.startOfDay(for: selectedDate), items.sorted {
                if $0.startAt == $1.startAt { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return $0.startAt < $1.startAt
            })]
        }

        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.startAt) }
        return groups.keys.sorted().map { date in
            (date, groups[date]?.sorted { $0.startAt < $1.startAt } ?? [])
        }
    }

    private func sectionTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}

private struct AgendaRow: View {
    let item: CalendarItem
    let query: String
    let calendarRed: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(CalendarColorKey.color(for: item.colorKey))
                .frame(width: 10, height: 10)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 3) {
                highlightedTitle
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var highlightedTitle: Text {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let range = item.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(item.title)
        }
        let before = String(item.title[..<range.lowerBound])
        let match = String(item.title[range])
        let after = String(item.title[range.upperBound...])
        return Text(before) + Text(match).foregroundColor(calendarRed) + Text(after)
    }

    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = item.isAllDay ? "All-day" : "\(formatter.string(from: item.startAt)) - \(formatter.string(from: item.endAt))"
        if let location = item.location, !location.isEmpty {
            return "\(time) · \(location)"
        }
        return time
    }
}

private struct CalendarEventEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var isPresented: Bool
    @State private var title = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var eventType: FlyrCalendarEventType = .doorKnock
    @State private var contacts: [Contact] = []
    @State private var selectedContact: Contact?
    @State private var contactSearchText = ""
    @State private var isLoadingContacts = false
    @State private var campaigns: [CalendarCampaignOption] = []
    @State private var selectedCampaign: CalendarCampaignOption?
    @State private var campaignSearchText = ""
    @State private var isLoadingCampaigns = false
    @State private var recurrenceRule: CalendarRecurrenceRule = .none
    @State private var recurrenceEnds = false
    @State private var recurrenceUntil: Date
    @State private var notes = ""
    @State private var location = ""
    @StateObject private var locationAuto = UseAddressAutocomplete()
    @State private var colorKey: CalendarColorKey = .green
    @FocusState private var focusedField: EventEditorField?

    let onSave: (FlyrCalendarEvent) -> Void

    init(isPresented: Binding<Bool>, initialStart: Date, onSave: @escaping (FlyrCalendarEvent) -> Void) {
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: initialStart) ?? initialStart
        _isPresented = isPresented
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: end)
        _recurrenceUntil = State(initialValue: Calendar.current.date(byAdding: .month, value: 3, to: initialStart) ?? initialStart)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                    AddressSearchField(
                        auto: locationAuto,
                        onPick: { suggestion in
                            location = locationText(from: suggestion)
                        },
                        onSubmitQuery: { query in
                            location = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        },
                        placeholder: "Location"
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                }

                Section("Type") {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(selectableEventTypes) { type in
                            Button {
                                selectEventType(type)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type == eventType ? "checkmark.circle.fill" : type.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 20)
                                    Text(type.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(type == eventType ? .white : .primary)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(type == eventType ? CalendarColorKey.red.color : Color(.tertiarySystemFill))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $recurrenceRule) {
                        ForEach(CalendarRecurrenceRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    .pickerStyle(.menu)

                    if recurrenceRule != .none {
                        Toggle("End repeat", isOn: $recurrenceEnds)
                        if recurrenceEnds {
                            DatePicker("Until", selection: $recurrenceUntil, displayedComponents: [.date])
                        }
                    }
                }

                Section("Lead") {
                    if let selectedContact {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedContact.fullName)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(selectedContact.address)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Clear") {
                                self.selectedContact = nil
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        TextField("Search leads", text: $contactSearchText)
                            .focused($focusedField, equals: .leadSearch)

                        if contactSearchQuery.isEmpty {
                            EmptyView()
                        } else if isLoadingContacts {
                            ProgressView()
                        } else if filteredContacts.isEmpty {
                            Text(contacts.isEmpty ? "No leads found" : "No matching leads")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(filteredContacts.prefix(5)) { contact in
                                Button {
                                    selectContact(contact)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.crop.circle")
                                            .foregroundColor(.secondary)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contact.fullName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(2)
                                            Text(contact.address)
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Campaign") {
                    if let selectedCampaign {
                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCampaign.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                if let region = selectedCampaign.region, !region.isEmpty {
                                    Text(region)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button("Clear") {
                                self.selectedCampaign = nil
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        TextField("Search campaigns", text: $campaignSearchText)
                            .focused($focusedField, equals: .campaignSearch)

                        if campaignSearchQuery.isEmpty {
                            EmptyView()
                        } else if isLoadingCampaigns {
                            ProgressView()
                        } else if filteredCampaigns.isEmpty {
                            Text(campaigns.isEmpty ? "No campaigns found" : "No matching campaigns")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(filteredCampaigns.prefix(5)), id: \.id) { campaign in
                                Button {
                                    selectCampaign(campaign)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "map")
                                            .foregroundColor(.secondary)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(campaign.displayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(2)
                                            if let region = campaign.region, !region.isEmpty {
                                                Text(region)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Color") {
                    HStack {
                        ForEach(CalendarColorKey.allCases) { key in
                            Circle()
                                .fill(key.color)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if key == colorKey {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .onTapGesture { colorKey = key }
                        }
                    }
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadContacts()
                await loadCampaigns()
            }
            .onAppear {
                if locationAuto.query.isEmpty {
                    locationAuto.query = location
                }
            }
            .onChange(of: location) { _, newValue in
                if locationAuto.query != newValue {
                    locationAuto.query = newValue
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let normalizedEnd = max(endDate, Calendar.current.date(byAdding: .minute, value: 15, to: startDate) ?? startDate)
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let resolvedTitle = trimmedTitle.isEmpty
                            ? eventType.defaultTitle(contactName: selectedContact?.fullName, campaignName: selectedCampaign?.displayName)
                            : trimmedTitle
                        let resolvedLocation = locationAuto.query.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? selectedContact?.address
                        onSave(
                            FlyrCalendarEvent(
                                title: resolvedTitle,
                                startAt: startDate,
                                endAt: normalizedEnd,
                                isAllDay: isAllDay,
                                eventType: eventType.rawValue,
                                contactId: selectedContact?.id,
                                contactName: selectedContact?.fullName,
                                contactAddress: selectedContact?.address,
                                campaignId: selectedCampaign?.id,
                                campaignName: selectedCampaign?.displayName,
                                recurrenceRule: recurrenceRule.rawValue,
                                recurrenceUntil: recurrenceRule == .none || !recurrenceEnds ? nil : recurrenceUntil,
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                location: resolvedLocation,
                                colorKey: colorKey.rawValue
                            )
                        )
                        closeSheet()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        true
    }

    private var selectableEventTypes: [FlyrCalendarEventType] {
        FlyrCalendarEventType.manualCreationTypes
    }

    private var contactSearchQuery: String {
        contactSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var campaignSearchQuery: String {
        campaignSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func locationText(from suggestion: AddressSuggestion) -> String {
        if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
            return "\(suggestion.title), \(subtitle)"
        }
        return suggestion.title
    }

    private var filteredContacts: [Contact] {
        let query = contactSearchQuery.lowercased()
        let sorted = contacts.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        guard !query.isEmpty else { return [] }
        return sorted.filter { contact in
            [
                contact.fullName,
                contact.address,
                contact.phone ?? "",
                contact.email ?? "",
                contact.notes ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var filteredCampaigns: [CalendarCampaignOption] {
        let query = campaignSearchQuery.lowercased()
        let sorted = campaigns.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !query.isEmpty else { return [] }
        return sorted.filter { campaign in
            [
                campaign.displayName,
                campaign.region ?? "",
                campaign.details ?? "",
                campaign.status ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private func selectEventType(_ type: FlyrCalendarEventType) {
        let shouldRefreshTitle = titleLooksGeneratedByManualType(title)
        eventType = type
        colorKey = CalendarColorKey(rawValue: type.defaultColorKey) ?? colorKey
        if shouldRefreshTitle {
            title = type.defaultTitle(contactName: selectedContact?.fullName, campaignName: selectedCampaign?.displayName)
        }
    }

    private func selectContact(_ contact: Contact) {
        selectedContact = contact
        contactSearchText = ""
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            location = contact.address
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = eventType.defaultTitle(contactName: contact.fullName)
        }
        focusedField = nil
    }

    private func selectCampaign(_ campaign: CalendarCampaignOption) {
        selectedCampaign = campaign
        campaignSearchText = ""
        if titleLooksGeneratedByManualType(title) {
            title = eventType.defaultTitle(contactName: selectedContact?.fullName, campaignName: campaign.displayName)
        }
        focusedField = nil
    }

    private func titleLooksGeneratedByManualType(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return FlyrCalendarEventType.manualCreationTypes.contains { type in
            trimmed == type.title || trimmed.hasPrefix("\(type.title):")
        }
    }

    private func loadContacts() async {
        guard contacts.isEmpty else { return }
        let userId = await MainActor.run { AuthManager.shared.user?.id }
        let workspaceId = await MainActor.run { WorkspaceContext.shared.workspaceId }
        guard let userId else { return }

        await MainActor.run { isLoadingContacts = true }
        let loaded = (try? await ContactsService.shared.fetchContacts(userID: userId, workspaceId: workspaceId)) ?? []
        await MainActor.run {
            contacts = loaded
            isLoadingContacts = false
        }
    }

    private func loadCampaigns() async {
        guard campaigns.isEmpty else { return }

        let cachedCampaigns = await MainActor.run { CampaignV2Store.shared.campaigns }
        if !cachedCampaigns.isEmpty {
            await MainActor.run {
                campaigns = cachedCampaigns.map(CalendarCampaignOption.init(campaign:))
            }
            return
        }

        let workspaceId = await MainActor.run { WorkspaceContext.shared.workspaceId }
        await MainActor.run { isLoadingCampaigns = true }
        let loaded = (try? await CampaignsAPI.shared.fetchCampaignsMetadata(workspaceId: workspaceId)) ?? []
        await MainActor.run {
            campaigns = loaded.map(CalendarCampaignOption.init(row:))
            isLoadingCampaigns = false
        }
    }

    private func cancel() {
        closeSheet()
    }

    private func closeSheet() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.async {
            isPresented = false
            dismiss()
        }
    }

    private enum EventEditorField: Hashable {
        case title
        case location
        case leadSearch
        case campaignSearch
        case notes
    }

}

private struct CalendarCampaignOption: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let region: String?
    let details: String?
    let status: String?

    init(campaign: CampaignV2) {
        id = campaign.id
        displayName = campaign.name
        region = campaign.seedQuery
        details = nil
        status = campaign.status.rawValue
    }

    init(row: CampaignDBRow) {
        id = row.id
        displayName = row.title
        region = row.region
        details = row.description
        status = row.status?.rawValue
    }
}

private struct CalendarViewMenuButton: UIViewRepresentable {
    let level: CalendarLevel
    let monthMode: MonthDisplayMode
    let dayMode: DayDisplayMode
    let setMonthMode: (MonthDisplayMode) -> Void
    let setDayMode: (DayDisplayMode) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.menu = context.coordinator.makeMenu()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: CalendarViewMenuButton

        init(parent: CalendarViewMenuButton) {
            self.parent = parent
        }

        func makeMenu() -> UIMenu {
            let monthModes = MonthDisplayMode.allCases.filter { $0 != .stacked && $0 != .compact }
            let dayModes = DayDisplayMode.allCases.filter { $0 != .multiDay }

            let monthActions = monthModes.map { mode in
                UIAction(
                    title: mode.title,
                    image: UIImage(systemName: mode.symbol),
                    state: parent.level != .day && mode == parent.monthMode ? .on : .off
                ) { [weak self] _ in
                    self?.parent.setMonthMode(mode)
                }
            }

            let dayActions = dayModes.map { mode in
                UIAction(
                    title: mode.title,
                    image: UIImage(systemName: mode.symbol),
                    state: parent.level == .day && mode == parent.dayMode ? .on : .off
                ) { [weak self] _ in
                    self?.parent.setDayMode(mode)
                }
            }

            return UIMenu(children: [
                UIMenu(options: .displayInline, children: monthActions),
                UIMenu(options: .displayInline, children: dayActions)
            ])
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    NavigationStack {
        CalendarTabView()
            .environmentObject(AppUIState())
    }
}
