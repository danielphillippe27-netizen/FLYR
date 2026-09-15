import SwiftUI
import Combine
import Supabase

private struct HiringPosting: Decodable, Identifiable {
    let id: UUID
    let provider: String
    let url: String
    let postedAt: String
    let salaryMin: Double?
    let salaryMax: Double?
    let currency: String?
    let companyUrl: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let sourceUrl: String?
    let closedAt: String?
    let hiringTeam: [HiringTeamMember]?
}

private struct HiringTeamMember: Decodable {
    let name: String?
    let role: String?
    let profileUrl: String?
}

private struct HiringLead: Decodable, Identifiable {
    let id: UUID
    let company: String
    let title: String
    let location: String
    let country: String
    let category: String?
    let firstSeenAt: String
    let latestPostingSeenAt: String
    let lastSeenAt: String
    var status: String
    let postings: [HiringPosting]
}

private struct HiringFeed: Decodable {
    struct Source: Decodable {
        let name: String
        let configured: Bool
        let coverage: String
        let mode: String?
        let collectionDescription: String?
        let attributionURL: String?
        let receivedLast24h: Int?
        let lastReceivedAt: String?
    }
    struct Run: Decodable, Identifiable {
        let id: UUID
        let country: String
        let status: String
        let startedAt: String
        let finishedAt: String?
        let fetched: Int
        let rejected: Int
        let available: Int?
        let errorMessage: String?
    }
    let leads: [HiringLead]
    let hasMore: Bool
    let source: Source
    let runs: [Run]
}

private enum HiringAPI {
    static func request(query: [URLQueryItem] = [], update: [String: String]? = nil) async throws -> Data {
        var components = URLComponents(url: Config.backendAPIURL.appendingPathComponent("api/salesperson/hiring-leads"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        let session = try await SupabaseManager.shared.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let update {
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(update)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "Could not reach Hiring Leads. Please try again."
            throw NSError(domain: "HiringLeads", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}

@MainActor
private final class HiringLeadsModel: ObservableObject {
    @Published var leads: [HiringLead] = []
    @Published var source: HiringFeed.Source?
    @Published var runs: [HiringFeed.Run] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var hasMore = false
    @Published var error: String?
    @Published var updating: Set<UUID> = []
    private var generation = UUID()
    private var offset = 0

    func load(country: String, status: String, search: String, days: Int, reset: Bool = true) async {
        if !reset && isLoading { return }
        if reset { generation = UUID(); offset = 0; leads = []; hasMore = false }
        let current = generation
        isLoading = true
        error = nil
        defer { if generation == current { isLoading = false; hasLoaded = true } }
        do {
            let data = try await HiringAPI.request(query: [
                URLQueryItem(name: "country", value: country), URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "q", value: search), URLQueryItem(name: "days", value: String(days)),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            try Task.checkCancellation()
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let feed = try decoder.decode(HiringFeed.self, from: data)
            guard current == generation else { return }
            let existing = Set(leads.map(\.id))
            leads.append(contentsOf: feed.leads.filter { !existing.contains($0.id) })
            offset += feed.leads.count
            hasMore = feed.hasMore
            source = feed.source
            runs = feed.runs
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func update(_ lead: HiringLead, status: String) async -> Bool {
        guard !updating.contains(lead.id) else { return false }
        updating.insert(lead.id)
        defer { updating.remove(lead.id) }
        do {
            _ = try await HiringAPI.request(update: ["leadId": lead.id.uuidString, "status": status])
            if let index = leads.firstIndex(where: { $0.id == lead.id }) { leads[index].status = status }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct HiringLeadsView: View {
    @StateObject private var model = HiringLeadsModel()
    @State private var country = "all"
    @State private var status = "all"
    @State private var search = ""
    @State private var days = 7

    private var queryKey: String { "\(country)|\(status)|\(days)|\(search)" }

    var body: some View {
        List {
            Section {
                Picker("Country", selection: $country) {
                    Text("Canada + USA").tag("all")
                    Text("Canada").tag("CA")
                    Text("USA").tag("US")
                }
                Picker("Posting found", selection: $days) {
                    Text("Last 24 hours").tag(1)
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("Last 90 days").tag(90)
                }
                Picker("My review status", selection: $status) {
                    Text("All").tag("all")
                    Text("New").tag("new")
                    Text("Saved").tag("saved")
                    Text("Contacted").tag("contacted")
                    Text("Dismissed").tag("dismissed")
                }
            }

            Section {
                if let source = model.source {
                    Label(source.configured ? "\(source.name) hiring feed" : "Source not connected",
                          systemImage: source.configured ? "calendar.badge.clock" : "link.badge.plus")
                        .font(.headline)
                    if !source.configured {
                        Text("Job-data access needs to be connected before daily collection can start.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if source.mode == "webhook", source.configured {
                        Text("\(source.receivedLast24h ?? 0) new postings received in the last 24 hours")
                            .font(.subheadline)
                        if let lastReceived = source.lastReceivedAt {
                            Text("Last received \(hiringDate(lastReceived))").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Waiting for the first posting.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(source.mode == "webhook" ? [] : latestRuns) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(run.country == "CA" ? "Canada" : "USA"): \(run.status.capitalized)")
                            Text("\(run.fetched) postings collected · \(hiringDate(run.finishedAt ?? run.startedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let available = run.available, run.status == "partial" {
                                Text("\(available) results reported by the source. \(run.rejected) records could not be read.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let message = run.errorMessage {
                                Text(message).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    if source.configured && source.mode != "webhook" && latestRuns.isEmpty {
                        Text("Waiting for the first collection.").foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Sources and coverage") {
                        Text(source.coverage).font(.caption).foregroundStyle(.secondary)
                        Text("A hiring signal may include multiple postings for the same company, title and location. Hiring contacts are shown only when supplied by the source.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(source.collectionDescription ?? "New employer postings in Canada and the USA.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let attribution = source.attributionURL.flatMap(hiringURL) {
                            Link("Jobs via \(source.name)", destination: attribution)
                        }
                    }
                }
            }

            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Try again") { Task { await reload() } }
                }
            }

            Section("Hiring leads · \(model.leads.count) loaded") {
                ForEach(model.leads) { lead in
                    NavigationLink {
                        HiringLeadDetail(lead: lead, model: model)
                            .onDisappear { Task { await reload() } }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(lead.company).font(.headline)
                                Spacer()
                                Text(lead.country).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text(lead.title).font(.subheadline)
                            Text(lead.location).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("Found \(hiringDate(lead.latestPostingSeenAt))")
                                Spacer()
                                Text(lead.status.capitalized)
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if model.isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
                else if model.hasLoaded && model.leads.isEmpty && model.error == nil {
                    ContentUnavailableView("No hiring leads yet", systemImage: "briefcase",
                        description: Text(model.source?.configured == true ? "Try a wider date range or different filters." : "New employer postings will appear here after a source is connected."))
                }
                if model.hasMore && !model.isLoading {
                    Button("Load more") { Task { await reload(reset: false) } }
                }
            }
        }
        .navigationTitle("Hiring Leads")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Company, role, location or industry")
        .task(id: queryKey) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private var latestRuns: [HiringFeed.Run] {
        ["CA", "US"].compactMap { country in model.runs.first { $0.country == country } }
    }

    private func reload(reset: Bool = true) async {
        await model.load(country: country, status: status, search: search, days: days, reset: reset)
    }
}

private struct HiringLeadDetail: View {
    let lead: HiringLead
    @ObservedObject var model: HiringLeadsModel
    @State private var updateError: String?
    private var current: HiringLead { model.leads.first { $0.id == lead.id } ?? lead }

    var body: some View {
        List {
            Section {
                Text(lead.company).font(.title2.bold())
                Text(lead.title).font(.headline)
                Label(lead.location, systemImage: "mappin.and.ellipse")
                Text(lead.country == "CA" ? "Canada" : "United States")
                if let category = lead.category { Text(category).foregroundStyle(.secondary) }
            }
            Section("My review") {
                LabeledContent("Status", value: current.status.capitalized)
                Menu("Change status") {
                    ForEach(["new", "saved", "contacted", "dismissed"], id: \.self) { status in
                        Button(status.capitalized) {
                            Task {
                                if !(await model.update(current, status: status)) { updateError = model.error }
                            }
                        }
                    }
                }.disabled(model.updating.contains(lead.id))
                Text("This status is private to you.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Discovery") {
                LabeledContent("First found", value: hiringDate(lead.firstSeenAt))
                LabeledContent("Latest posting found", value: hiringDate(lead.latestPostingSeenAt))
                LabeledContent("Last seen", value: hiringDate(lead.lastSeenAt))
                Text("First found is when WolfGrid collected this lead. The original posting dates are listed below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(lead.postings) { posting in
                Section(posting.provider == "adzuna" ? "Jobs by Adzuna" : posting.provider == "theirstack" ? "Via TheirStack" : posting.provider.capitalized) {
                    LabeledContent("Posted", value: hiringDate(posting.postedAt))
                    if let closed = posting.closedAt {
                        Label("Closed \(hiringDate(closed))", systemImage: "archivebox").foregroundStyle(.secondary)
                    }
                    if let sourceURL = posting.sourceUrl.flatMap(hiringURL), posting.sourceUrl != posting.url {
                        Link("View source listing", destination: sourceURL)
                    }
                    if let url = hiringURL(posting.url) { Link("View original posting", destination: url) }
                    if let minimum = posting.salaryMin {
                        LabeledContent("Listed salary minimum", value: salary(minimum, currency: posting.currency))
                    }
                    if let maximum = posting.salaryMax {
                        LabeledContent("Listed salary maximum", value: salary(maximum, currency: posting.currency))
                    }
                    if let url = posting.companyUrl.flatMap(hiringURL) { Link("Company website", destination: url) }
                    if let name = posting.contactName { LabeledContent("Hiring contact", value: name) }
                    if let email = posting.contactEmail { LabeledContent("Business email", value: email).textSelection(.enabled) }
                    if let phone = posting.contactPhone { LabeledContent("Business phone", value: phone).textSelection(.enabled) }
                    ForEach(Array((posting.hiringTeam ?? []).enumerated()), id: \.offset) { _, person in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(person.name ?? "Hiring contact").font(.headline)
                            if let role = person.role { Text(role).font(.subheadline).foregroundStyle(.secondary) }
                            if let url = person.profileUrl.flatMap(hiringURL) { Link("View hiring contact profile", destination: url) }
                        }
                    }
                    if posting.contactName == nil && posting.contactEmail == nil && posting.contactPhone == nil && (posting.hiringTeam ?? []).isEmpty {
                        Text("No hiring contact supplied by this source.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Hiring lead")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not save", isPresented: Binding(get: { updateError != nil }, set: { if !$0 { updateError = nil } })) {
            Button("OK", role: .cancel) { updateError = nil }
        } message: { Text(updateError ?? "Please try again.") }
    }

    private func salary(_ amount: Double, currency: String?) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0)))) \(currency ?? "(currency not supplied)")"
    }
}

private func hiringURL(_ value: String) -> URL? {
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
          ["https", "http"].contains(scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
    return url
}

private func hiringDate(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: value)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: value)
    }
    return date?.formatted(date: .abbreviated, time: .shortened) ?? value
}
