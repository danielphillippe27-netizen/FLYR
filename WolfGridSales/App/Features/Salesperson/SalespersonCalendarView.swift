import SwiftUI

struct SalespersonCalendarView: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var items: [SalespersonCalendarItem] = []
    @State private var isLoading = false

    private let calendar = Calendar.current
    private let accent = Color.red
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    agenda
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        selectedDate = Date()
                        visibleMonth = Date()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task(id: monthKey) { await loadMonth() }
            .refreshable { await loadMonth() }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))

            Spacer()

            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Color.primary)
        .padding(.top, 4)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(monthDates.indices, id: \.self) { index in
                if let date = monthDates[index] {
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 15, weight: isSelected(date) ? .bold : .regular))
                            Circle()
                                .fill(hasEvents(on: date) ? accent : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .foregroundStyle(isSelected(date) ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(isSelected(date) ? accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
                } else {
                    Color.clear.frame(height: 42)
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.headline)
                Spacer()
                Text("\(selectedItems.count) \(selectedItems.count == 1 ? "meeting" : "meetings")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if selectedItems.isEmpty {
                ContentUnavailableView(
                    "No meetings",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Your scheduled meetings for this day will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(selectedItems) { item in
                    eventRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ item: SalespersonCalendarItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: item.eventType))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                Text(timeRange(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let contact = item.contactName, !contact.isEmpty {
                    Label(contact, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let location = item.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.attendeeEmails.isEmpty {
                    Label(item.attendeeEmails.joined(separator: ", "), systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let joinURL = item.conferenceJoinURL {
                Button { openURL(joinURL) } label: {
                    Image(systemName: "video.fill")
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(accent, in: Circle())
                }
                .accessibilityLabel("Join meeting")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectedItems: [SalespersonCalendarItem] {
        items.filter { calendar.isDate($0.startAt, inSameDayAs: selectedDate) }
            .sorted { $0.startAt < $1.startAt }
    }

    private var monthDates: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthKey: String {
        visibleMonth.formatted(.iso8601.year().month())
    }

    private func loadMonth() async {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return }
        isLoading = true
        let loaded = await SalespersonCalendarService.shared.fetchCalendarItems(start: interval.start, end: interval.end)
        items = loaded.filter(isMeeting)
        isLoading = false
    }

    private func moveMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = next
        selectedDate = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func hasEvents(on date: Date) -> Bool {
        items.contains { calendar.isDate($0.startAt, inSameDayAs: date) }
    }

    private func isMeeting(_ item: SalespersonCalendarItem) -> Bool {
        item.conferenceProvider != nil || item.eventType == SalespersonCalendarEventType.appointment.rawValue
    }

    private func timeRange(for item: SalespersonCalendarItem) -> String {
        "\(item.startAt.formatted(date: .omitted, time: .shortened)) – \(item.endAt.formatted(date: .omitted, time: .shortened))"
    }

    private func color(for eventType: String) -> Color {
        switch eventType {
        case SalespersonCalendarEventType.call.rawValue: return .green
        case SalespersonCalendarEventType.followUp.rawValue: return .orange
        case SalespersonCalendarEventType.task.rawValue: return .blue
        default: return accent
        }
    }
}

#Preview {
    SalespersonCalendarView()
}
