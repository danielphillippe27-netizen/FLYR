import SwiftUI

struct WolfyCoachView: View {
    @ObservedObject var coach: WolfyCoachStore
    let user: UUID
    let workspace: UUID
    var summary: WolfyHomeSummary? = nil
    @State private var showingKPIs = false
    @State private var question = ""
    @FocusState private var focused: Bool
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        WolfyPocketPet().frame(width: 44, height: 50)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ask Wolfy").font(.title2.weight(.semibold))
                            Text("Ask me about your performance.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if coach.messages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["How am I doing?", "What should I do next?", "Am I on pace?", "Why are my leads down?", "How's my week?", "Who should I follow up with?"], id: \.self) { prompt in
                                    Button(prompt) { send(prompt) }
                                        .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                        .disabled(coach.sending || coach.reporting)
                                }
                            }
                        }
                    }
                    DisclosureGroup("Coaching context") {
                        controls
                        Text("Questions and recent messages are sent with your synced performance summary. Team analysis is available only with permission.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.font(.caption).foregroundStyle(.secondary)
                    ForEach(coach.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == "user" ? "You" : "Wolfy · \(message.label ?? "Coach")").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(message.content).textSelection(.enabled)
                            if !message.evidence.isEmpty {
                                DisclosureGroup("Verified figures · \(message.evidence.count)") {
                                    ForEach(message.evidence) { fact in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(fact.label): \(fact.display)").font(.subheadline.bold())
                                            Text(fact.period).font(.caption)
                                            Text("Source: \(fact.source)").font(.caption2).foregroundStyle(.secondary)
                                            if let note = fact.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                                        }.padding(.vertical, 4)
                                    }
                                }.font(.caption)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == "user" ? Color(uiColor: .secondarySystemBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if coach.sending { ProgressView("Wolfy is thinking…") }
                    if let error = coach.error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        if !coach.messages.isEmpty {
                            Button("Retry question") { Task { await coach.retry(user: user, workspace: workspace) } }.disabled(coach.sending || coach.reporting)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }
            .onChange(of: coach.messages.count) { _, _ in withAnimation { scroll.scrollTo("bottom", anchor: .bottom) } }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom) {
                    TextField("Ask Wolfy…", text: $question, axis: .vertical).lineLimit(1...5).focused($focused)
                        .onChange(of: question) { _, value in if value.count > 1000 { question = String(value.prefix(1000)) } }
                    Button { send(question) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .accessibilityLabel("Send question")
                        .disabled(coach.sending || coach.reporting || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
            }
        }.background(Color(uiColor: .systemBackground)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Clear") { coach.clearConversation() }.disabled(coach.sending || coach.reporting) }
        .task { await coach.configure(scope: coach.analysisScope, days: coach.historyDays, user: user, workspace: workspace) }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if coach.canCoachTeam || coach.analysisScope == "team" {
                Picker("Coaching scope", selection: Binding(get: { coach.analysisScope }, set: { value in
                    Task { await coach.configure(scope: value, days: coach.historyDays, user: user, workspace: workspace) }
                })) {
                    Text("My performance").tag("self")
                    Text("My team").tag("team")
                }.pickerStyle(.segmented).disabled(coach.reporting || coach.sending)
            }
            HStack {
                Picker("History", selection: Binding(get: { coach.historyDays }, set: { days in
                    Task { await coach.configure(scope: coach.analysisScope, days: days, user: user, workspace: workspace) }
                })) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("365 days").tag(365)
                }.disabled(coach.reporting || coach.sending)
                Spacer()
                Button("All KPIs") { showingKPIs = true }.disabled(coach.report == nil)
            }
            if coach.reporting { ProgressView("Loading field performance…") }
            if coach.report == nil && !coach.reporting {
                Button("Load performance data") { Task { await coach.configure(scope: coach.analysisScope, days: coach.historyDays, user: user, workspace: workspace) } }
            }
        }
        .sheet(isPresented: $showingKPIs) {
            if let report = coach.report { WolfyKPIReportView(report: report) }
        }
    }
    private func send(_ value: String) {
        question = ""; focused = false
        Task { await coach.ask(value, user: user, workspace: workspace) }
    }
}


struct WolfyKPIReportView: View {
    let report: WolfyKPIReport
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var group = "scope"
    @State private var period = "today"
    private var periods: [String] {
        Array(Set(report.facts.filter { $0.group == group }.map { $0.id.split(separator: ".").dropFirst().first.map(String.init) ?? "" })).sorted()
    }
    private var visible: [WolfyKPIFact] {
        report.facts.filter { fact in
            fact.group == group && (search.isEmpty ? fact.id.hasPrefix("\(group).\(period).") : fact.label.localizedCaseInsensitiveContains(search) || fact.period.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        Picker("View", selection: $group) {
                            ForEach(report.groups) { item in Text(item.label).tag(item.id) }
                        }
                    } label: {
                        selectionLabel("View", report.groups.first { $0.id == group }?.label ?? "Performance")
                    }
                    Menu {
                        Picker("Period", selection: $period) {
                            ForEach(periods, id: \.self) { value in
                                Text(periodLabel(value).components(separatedBy: " · ").first ?? value).tag(value)
                            }
                        }
                    } label: {
                        selectionLabel("Period", periodLabel(period).components(separatedBy: " · ").first ?? period)
                    }
                    Text("Reporting timezone: \(report.timezone)").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(visible) { fact in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(fact.label).font(.subheadline)
                            Text(fact.display).font(.title3.bold()).monospacedDigit()
                            Text(fact.period).font(.caption).foregroundStyle(.secondary)
                            if let note = fact.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                }
                Section("Data coverage") {
                    ForEach(report.coverage, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $search, prompt: "Find a KPI or comparison")
            .navigationTitle(report.scope == "team" ? "Team KPIs" : "My KPIs")
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: group) { _, _ in if !periods.contains(period) { period = periods.first ?? "today" } }
        }
    }
    private func selectionLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(value).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.caption)
            }.foregroundStyle(.primary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func periodLabel(_ value: String) -> String {
        report.facts.first { $0.group == group && $0.id.hasPrefix("\(group).\(value).") }?.period ?? value
    }
}
