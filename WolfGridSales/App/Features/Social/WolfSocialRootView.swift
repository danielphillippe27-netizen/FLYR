import AVFoundation
import AVKit
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WolfSocialViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable { case overview, create, calendar, inbox, library, analytics, connections; var id: String { rawValue }; var title: String { rawValue.capitalized } }
    @Published var section: Section
    @Published var workspace: WolfSocialWorkspace?
    @Published var connections: [WolfSocialConnection] = []
    @Published var providerAvailability: [String: WolfSocialProviderAvailability] = [:]
    @Published var posts: [WolfSocialPost] = []
    @Published var media: [WolfSocialMediaAsset] = []
    @Published var threads: [WolfSocialThread] = []
    @Published var analytics = WolfSocialAnalytics(periodDays: 30, totals: [:], posts: nil)
    @Published var canCreateLead = false
    @Published var isLoading = false
    @Published var uploadProgress: Double?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    private var uploadTask: Task<Void, Never>?

    init(section: Section = .overview) {
        self.section = section
    }

    func refresh() async {
        isLoading = true
        do {
            async let workspaceValue = WolfSocialAPIClient.shared.loadWorkspace()
            async let connectionValue = WolfSocialAPIClient.shared.connections()
            async let postValue = WolfSocialAPIClient.shared.posts()
            async let mediaValue = WolfSocialAPIClient.shared.media()
            async let inboxValue = WolfSocialAPIClient.shared.inbox()
            async let analyticsValue = WolfSocialAPIClient.shared.analytics()
            let values = try await (workspaceValue, connectionValue, postValue, mediaValue, inboxValue, analyticsValue)
            workspace = values.0.0; canCreateLead = values.0.1; connections = values.1.0; providerAvailability = values.1.1; posts = values.2; media = values.3; threads = values.4; analytics = values.5
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func upload(data: Data, fileName: String, mimeType: String, durationSeconds: Double? = nil, completion: @escaping (WolfSocialMediaAsset) -> Void) {
        uploadTask?.cancel()
        uploadProgress = 0
        uploadTask = Task {
            do {
                let asset = try await WolfSocialAPIClient.shared.uploadMedia(data: data, fileName: fileName, mimeType: mimeType, durationSeconds: durationSeconds) { value in
                    await MainActor.run { self.uploadProgress = value }
                }
                guard !Task.isCancelled else { return }
                media.insert(asset, at: 0); completion(asset); uploadProgress = nil
            } catch is CancellationError { uploadProgress = nil }
            catch { errorMessage = error.localizedDescription; uploadProgress = nil }
        }
    }

    func cancelUpload() { uploadTask?.cancel(); uploadTask = nil; uploadProgress = nil }

    func disconnect(_ connection: WolfSocialConnection) async {
        do {
            try await WolfSocialAPIClient.shared.disconnect(connectionID: connection.id)
            connections.removeAll { $0.id == connection.id }
            successMessage = "\(connection.accountName ?? connection.platform.title) disconnected."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WolfSocialRootView: View {
    @StateObject private var model: WolfSocialViewModel
    @StateObject private var oauth = WolfSocialOAuthSession()
    @Environment(\.scenePhase) private var scenePhase

    init(initialSection: WolfSocialViewModel.Section = .overview) {
        _model = StateObject(wrappedValue: WolfSocialViewModel(section: initialSection))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WolfSocialViewModel.Section.allCases) { section in
                            Button(section.title) { model.section = section }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(model.section == section ? Color.white : Color.primary)
                                .background(model.section == section ? Color.black : Color(.secondarySystemBackground), in: Capsule())
                        }
                    }.padding(.horizontal).padding(.vertical, 10)
                }
                Divider()
                content
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .wolfSocialOAuthCompleted)) { notification in
                if let url = notification.object as? URL {
                    let status = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "status" })?.value
                    let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "error" })?.value
                    if status == "success" { model.successMessage = "Social account connected." } else { model.errorMessage = error ?? "Connection was not completed." }
                    Task { await model.refresh(); model.section = .connections }
                } else if let error = notification.object as? Error { model.errorMessage = error.localizedDescription }
            }
            .alert("WolfSocial", isPresented: Binding(get: { model.errorMessage != nil || model.successMessage != nil }, set: { if !$0 { model.errorMessage = nil; model.successMessage = nil } })) {
                Button("OK") { model.errorMessage = nil; model.successMessage = nil }
            } message: { Text(model.errorMessage ?? model.successMessage ?? "") }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .overview: WolfSocialOverview(model: model)
        case .create: WolfSocialComposer(model: model)
        case .calendar: WolfSocialCalendar(model: model)
        case .inbox: WolfSocialInbox(model: model)
        case .library: WolfSocialLibrary(model: model)
        case .analytics: WolfSocialAnalyticsView(model: model)
        case .connections: WolfSocialConnections(model: model, oauth: oauth)
        }
    }
}

private struct WolfSocialOverview: View {
    @ObservedObject var model: WolfSocialViewModel
    var body: some View { ScrollView { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
        metric("Accounts", model.connections.filter { $0.status == "active" }.count, "link")
        metric("Scheduled", model.posts.filter { $0.status == "scheduled" }.count, "calendar")
        metric("Need reply", model.threads.filter(\.needsReply).count, "message")
        metric("Views", Int(model.analytics.totals["views"] ?? 0), "chart.bar")
    }.padding() } }
    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(.red); Text(value.formatted()).font(.title.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)) }
}

private struct WolfSocialComposer: View {
    @ObservedObject var model: WolfSocialViewModel
    @State private var caption = ""
    @State private var captionOverrides: [String: String] = [:]
    @State private var wolfeySuggestions: [String] = []
    @State private var title = ""
    @State private var format = "reel"
    @State private var selectedConnections = Set<String>()
    @State private var selectedAssets: [WolfSocialMediaAsset] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingFiles = false
    @State private var scheduled = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var settingsByConnection: [String: WolfSocialTargetSettings] = [:]
    @State private var creatorInfoByConnection: [String: WolfSocialTikTokCreatorInfo] = [:]
    @State private var creatorInfoLoading = Set<String>()
    @State private var creatorInfoErrors: [String: String] = [:]
    @State private var saving = false

    var body: some View {
        Form {
            accountSection
            youtubeSection
            linkedinSection
            contentSection
            mediaSection
            tiktokPreviewSection
            tiktokSection
            timingSection
            actionSection
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .movie]) { result in
            if case .success(let url) = result { importFile(url) }
        }
        .onChange(of: photoItems) { _, items in
            Task { await importPhotos(items) }
        }
    }

    @ViewBuilder private var accountSection: some View {
        Section("Exact accounts") {
            if model.connections.isEmpty {
                Button("Connect an account") { model.section = .connections }
            } else {
                ForEach(model.connections.filter { $0.status == "active" }) { connection in
                    VStack(alignment: .leading) {
                        Toggle(isOn: Binding(
                            get: { selectedConnections.contains(connection.id) },
                            set: { selected in
                                if selected {
                                    selectedConnections.insert(connection.id)
                                    if connection.platform == .tiktok { Task { await loadCreatorInfo(for: connection) } }
                                } else {
                                    selectedConnections.remove(connection.id)
                                }
                            }
                        )) {
                            Label(connection.accountName ?? connection.platform.title, systemImage: connection.platform.systemImage)
                        }
                        if selectedConnections.contains(connection.id) {
                            TextField("Optional caption override", text: Binding(get: { captionOverrides[connection.id] ?? "" }, set: { captionOverrides[connection.id] = $0 }), axis: .vertical)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var youtubeSection: some View {
        ForEach(selectedConnectionModels.filter { $0.platform == .youtube }) { connection in
            Section("YouTube · \(connection.accountName ?? "Shorts")") {
                TextField("Short title", text: $title)
                Picker("Privacy", selection: stringSetting(connection.id, \.privacyStatus, default: "private")) {
                    Text("Private").tag("private")
                    Text("Unlisted").tag("unlisted")
                    Text("Public").tag("public")
                }
                Picker("Audience", selection: optionalBoolSetting(connection.id, \.madeForKids)) {
                    Text("Choose…").tag(Optional<Bool>.none)
                    Text("No, not made for kids").tag(Optional(false))
                    Text("Yes, made for kids").tag(Optional(true))
                }
            }
        }
    }

    @ViewBuilder private var linkedinSection: some View {
        ForEach(selectedConnectionModels.filter { $0.platform == .linkedin }) { connection in
            Section("LinkedIn · \(connection.accountName ?? "Profile")") {
                if connection.accountType == "organization" {
                    LabeledContent("Publishing as", value: "Company Page")
                    LabeledContent("Verified Page role", value: connection.pageRole == "CONTENT_ADMIN" ? "Content admin" : "Administrator")
                } else {
                    Picker("Visibility", selection: stringSetting(connection.id, \.visibility, default: "PUBLIC")) {
                        Text("Anyone").tag("PUBLIC")
                        Text("Connections").tag("CONNECTIONS")
                    }
                }
                Toggle("Disable resharing", isOn: boolSetting(connection.id, \.disableReshare))
                Text("Text, up to twenty images, or one video are supported. Company Pages require LinkedIn Community Management approval.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var contentSection: some View {
        Section("Content") {
            TextField("Caption", text: $caption, axis: .vertical).lineLimit(4...10)
            Button { Task { await requestWolfeyCaptions() } } label: { Label("Ask Wolfey for variants", systemImage: "sparkles") }
                .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(wolfeySuggestions, id: \.self) { suggestion in
                Button { caption = suggestion } label: { Text(suggestion).font(.caption).foregroundStyle(.primary) }
            }
            Picker("Format", selection: $format) {
                Text("Feed").tag("feed")
                Text("Carousel").tag("carousel")
                Text("Reel / short").tag("reel")
                Text("Story").tag("story")
            }
        }
    }

    @ViewBuilder private var mediaSection: some View {
        Section("Media") {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                Label("Choose photos or videos", systemImage: "photo.on.rectangle")
            }
            Button { showingFiles = true } label: { Label("Import a file", systemImage: "folder") }
            ForEach(selectedAssets) { asset in Text(asset.originalName).lineLimit(1) }
            if let progress = model.uploadProgress {
                ProgressView(value: progress)
                Button("Cancel upload", role: .destructive) { model.cancelUpload() }
            }
        }
    }

    @ViewBuilder private var tiktokSection: some View {
        ForEach(selectedConnectionModels.filter { $0.platform == .tiktok }) { connection in
            Section("TikTok approval · \(connection.accountName ?? "Creator")") {
                if creatorInfoLoading.contains(connection.id) {
                    HStack { ProgressView(); Text("Loading live creator settings…").foregroundStyle(.secondary) }
                } else if let error = creatorInfoErrors[connection.id] {
                    VStack(alignment: .leading) {
                        Text(error).foregroundStyle(.red)
                        Button("Try again") { Task { await loadCreatorInfo(for: connection) } }
                    }
                }
                Picker("Privacy", selection: stringSetting(connection.id, \.privacyLevel)) {
                    Text("Choose…").tag("")
                    ForEach(tikTokPrivacyOptions(for: connection.id), id: \.self) { option in
                        Text(tikTokPrivacyLabel(option)).tag(option)
                    }
                }
                .disabled(creatorInfoByConnection[connection.id] == nil)
                Toggle("Allow comments", isOn: boolSetting(connection.id, \.allowComments))
                    .disabled(creatorInfoByConnection[connection.id]?.commentsDisabled != false)
                if !isTikTokPhotoPost {
                    Toggle("Allow Duet", isOn: boolSetting(connection.id, \.allowDuet))
                        .disabled(creatorInfoByConnection[connection.id]?.duetDisabled != false)
                    Toggle("Allow Stitch", isOn: boolSetting(connection.id, \.allowStitch))
                        .disabled(creatorInfoByConnection[connection.id]?.stitchDisabled != false)
                }
                Toggle("Commercial content", isOn: Binding(
                    get: { settingsByConnection[connection.id]?.commercialContent ?? false },
                    set: { enabled in
                        var settings = settingsByConnection[connection.id] ?? WolfSocialTargetSettings()
                        settings.commercialContent = enabled
                        if !enabled { settings.yourBrand = false; settings.brandContent = false }
                        settingsByConnection[connection.id] = settings
                    }
                ))
                if settingsByConnection[connection.id]?.commercialContent == true {
                    Toggle("Your brand", isOn: boolSetting(connection.id, \.yourBrand))
                    Toggle("Branded content / another brand", isOn: Binding(
                        get: { settingsByConnection[connection.id]?.brandContent ?? false },
                        set: { enabled in
                            var settings = settingsByConnection[connection.id] ?? WolfSocialTargetSettings()
                            settings.brandContent = enabled
                            if enabled, let privacy = settings.privacyLevel, !["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS"].contains(privacy) {
                                settings.privacyLevel = nil
                            }
                            settingsByConnection[connection.id] = settings
                        }
                    ))
                    if settingsByConnection[connection.id]?.yourBrand != true && settingsByConnection[connection.id]?.brandContent != true {
                        Text("You need to indicate if your content promotes yourself, a third party, or both.").font(.caption).foregroundStyle(.red)
                    } else if settingsByConnection[connection.id]?.brandContent == true {
                        Text("Your photo/video will be labeled as 'Paid partnership'.").font(.caption)
                    } else {
                        Text("Your photo/video will be labeled as 'Promotional content'.").font(.caption)
                    }
                }
                Toggle("AI-generated content", isOn: boolSetting(connection.id, \.aiGeneratedContent))
                Toggle(isOn: boolSetting(connection.id, \.musicUsageConfirmed)) {
                    Text(.init(settingsByConnection[connection.id]?.brandContent == true
                        ? "By posting, you agree to TikTok's [Branded Content Policy](https://www.tiktok.com/legal/page/global/bc-policy/en) and [Music Usage Confirmation](https://www.tiktok.com/legal/page/global/music-usage-confirmation/en)."
                        : "By posting, you agree to TikTok's [Music Usage Confirmation](https://www.tiktok.com/legal/page/global/music-usage-confirmation/en)."))
                }
                Toggle("I approve this exact post", isOn: boolSetting(connection.id, \.explicitConsent))
                if let seconds = creatorInfoByConnection[connection.id]?.maxVideoDurationSeconds, seconds > 0 {
                    Text("This account supports videos up to \(seconds) seconds.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var tiktokPreviewSection: some View {
        if selectedPlatforms.contains(.tiktok), let asset = selectedAssets.first {
            Section("TikTok content preview") {
                if let url = asset.previewURL, asset.mimeType.hasPrefix("image/") {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 360)
                } else if let url = asset.previewURL, asset.mimeType.hasPrefix("video/") {
                    VideoPlayer(player: AVPlayer(url: url)).frame(height: 320)
                }
                Text(caption.isEmpty ? "Add a caption before publishing." : caption)
                    .font(.callout)
                Text(asset.originalName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var timingSection: some View {
        Section("Timing") {
            Toggle("Schedule", isOn: $scheduled)
            if scheduled {
                DatePicker("Publish at", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button("Save draft") { Task { await save("draft") } }.disabled(saving)
            Button(scheduled ? "Approve & schedule" : "Approve & publish") {
                Task { await save(scheduled ? "schedule" : "publish") }
            }
            .fontWeight(.bold)
            .disabled(saving)
        }
    }

    private var selectedConnectionModels: [WolfSocialConnection] { model.connections.filter { selectedConnections.contains($0.id) } }
    private var selectedPlatforms: Set<WolfSocialPlatform> { Set(selectedConnectionModels.map(\.platform)) }
    private func importPhotos(_ items: [PhotosPickerItem]) async { for (index, item) in items.enumerated() { guard let data = try? await item.loadTransferable(type: Data.self) else { continue }; let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }); let ext = isVideo ? "mov" : "jpg"; let duration = isVideo ? await videoDurationSeconds(data: data, fileExtension: ext) : nil; model.upload(data: data, fileName: "ios-media-\(index + 1).\(ext)", mimeType: isVideo ? "video/quicktime" : "image/jpeg", durationSeconds: duration) { selectedAssets.append($0) } } }
    private func importFile(_ url: URL) { let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }; guard let data = try? Data(contentsOf: url) else { return }; let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"; Task { let duration = mime.hasPrefix("video/") ? await videoDurationSeconds(data: data, fileExtension: url.pathExtension) : nil; model.upload(data: data, fileName: url.lastPathComponent, mimeType: mime, durationSeconds: duration) { selectedAssets.append($0) } } }
    private func save(_ mode: String) async {
        guard let workspace = model.workspace, !selectedConnections.isEmpty else { model.errorMessage = "Choose at least one account."; return }
        if selectedAssets.isEmpty && selectedPlatforms.contains(where: { ![.facebook, .linkedin].contains($0) }) { model.errorMessage = "Add the media required by the selected platform."; return }
        if format == "story", selectedPlatforms.contains(.facebook) { model.errorMessage = "Facebook Page connections support posts and Reels, but not Stories."; return }
        if selectedPlatforms.contains(.youtube), title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.errorMessage = "YouTube requires a title."; return }
        if selectedPlatforms.contains(.youtube), selectedAssets.count != 1 || selectedAssets.first?.mimeType.hasPrefix("video/") != true { model.errorMessage = "YouTube Shorts requires exactly one video."; return }
        if selectedPlatforms.contains(.linkedin) {
            let linkedinVideos = selectedAssets.filter { $0.mimeType.hasPrefix("video/") }
            let linkedinImages = selectedAssets.filter { $0.mimeType.hasPrefix("image/") }
            if linkedinVideos.count > 1 { model.errorMessage = "LinkedIn supports one video per post."; return }
            if !linkedinVideos.isEmpty && !linkedinImages.isEmpty { model.errorMessage = "LinkedIn posts cannot mix images and video."; return }
        }
        if mode != "draft", selectedConnectionModels.contains(where: { $0.platform == .youtube && settingsByConnection[$0.id]?.madeForKids == nil }) { model.errorMessage = "Choose whether each YouTube video is made for kids."; return }
        for connection in selectedConnectionModels where connection.platform == .tiktok {
            guard let creator = creatorInfoByConnection[connection.id] else { model.errorMessage = creatorInfoErrors[connection.id] ?? "Wait for TikTok creator settings to load."; return }
            let settings = settingsByConnection[connection.id] ?? WolfSocialTargetSettings()
            if mode != "draft" {
                guard let privacy = settings.privacyLevel, creator.privacyLevelOptions.contains(privacy), settings.musicUsageConfirmed == true, settings.explicitConsent == true else { model.errorMessage = "Choose a live TikTok privacy option and confirm music rights and approval."; return }
                if settings.commercialContent == true, settings.yourBrand != true, settings.brandContent != true { model.errorMessage = "Indicate whether the TikTok post promotes your brand, another brand, or both."; return }
                if settings.commercialContent != true, settings.yourBrand == true || settings.brandContent == true { model.errorMessage = "Turn on TikTok commercial content disclosure before choosing a brand type."; return }
                if settings.brandContent == true, !["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS"].contains(privacy) { model.errorMessage = "TikTok branded content visibility cannot be private."; return }
                if let video = selectedAssets.first(where: { $0.mimeType.hasPrefix("video/") }), creator.maxVideoDurationSeconds > 0 {
                    guard let duration = video.durationSeconds else { model.errorMessage = "Video duration is unavailable. Upload the TikTok video again before publishing."; return }
                    if duration > Double(creator.maxVideoDurationSeconds) { model.errorMessage = "TikTok limits this account to videos of \(creator.maxVideoDurationSeconds) seconds or less."; return }
                }
            }
        }
        saving = true
        let targets = model.connections.filter { selectedConnections.contains($0.id) }.map { connection in
            let targetFormat = connection.platform == .youtube ? "short" : connection.platform == .tiktok ? (selectedAssets.allSatisfy { $0.mimeType.hasPrefix("image/") } ? "tiktok_photo" : "tiktok_video") : format
            let settings = settingsByConnection[connection.id] ?? WolfSocialTargetSettings()
            return WolfSocialPostTargetRequest(connectionId: connection.id, format: targetFormat, caption: captionOverrides[connection.id]?.isEmpty == false ? captionOverrides[connection.id]! : caption, title: connection.platform == .youtube ? title : nil, settings: settings)
        }
        let iso = ISO8601DateFormatter(); let request = WolfSocialPostRequest(socialWorkspaceId: workspace.id, assetIds: selectedAssets.map(\.id), mode: mode, scheduledFor: mode == "schedule" ? iso.string(from: scheduleDate) : nil, timezone: TimeZone.current.identifier, caption: caption, title: title.isEmpty ? nil : title, contentType: format, targets: targets)
        do { try await WolfSocialAPIClient.shared.createPost(request); model.successMessage = mode == "draft" ? "Draft saved." : mode == "schedule" ? "Post scheduled." : "Post approved and queued. TikTok may take a few minutes to process and appear on your profile."; caption = ""; title = ""; captionOverrides = [:]; wolfeySuggestions = []; selectedAssets = []; selectedConnections = []; settingsByConnection = [:]; creatorInfoByConnection = [:]; await model.refresh(); model.section = .calendar } catch { model.errorMessage = error.localizedDescription }
        saving = false
    }

    private func loadCreatorInfo(for connection: WolfSocialConnection) async {
        guard connection.platform == .tiktok, !creatorInfoLoading.contains(connection.id) else { return }
        creatorInfoLoading.insert(connection.id)
        creatorInfoErrors[connection.id] = nil
        do {
            creatorInfoByConnection[connection.id] = try await WolfSocialAPIClient.shared.tikTokCreatorInfo(connectionID: connection.id)
        } catch {
            creatorInfoErrors[connection.id] = error.localizedDescription
        }
        creatorInfoLoading.remove(connection.id)
    }

    private func stringSetting(_ connectionID: String, _ keyPath: WritableKeyPath<WolfSocialTargetSettings, String?>, default defaultValue: String = "") -> Binding<String> {
        Binding(get: { settingsByConnection[connectionID]?[keyPath: keyPath] ?? defaultValue }, set: { value in
            var settings = settingsByConnection[connectionID] ?? WolfSocialTargetSettings()
            settings[keyPath: keyPath] = value
            settingsByConnection[connectionID] = settings
        })
    }

    private func boolSetting(_ connectionID: String, _ keyPath: WritableKeyPath<WolfSocialTargetSettings, Bool?>) -> Binding<Bool> {
        Binding(get: { settingsByConnection[connectionID]?[keyPath: keyPath] ?? false }, set: { value in
            var settings = settingsByConnection[connectionID] ?? WolfSocialTargetSettings()
            settings[keyPath: keyPath] = value
            settingsByConnection[connectionID] = settings
        })
    }

    private func optionalBoolSetting(_ connectionID: String, _ keyPath: WritableKeyPath<WolfSocialTargetSettings, Bool?>) -> Binding<Bool?> {
        Binding(get: { settingsByConnection[connectionID]?[keyPath: keyPath] }, set: { value in
            var settings = settingsByConnection[connectionID] ?? WolfSocialTargetSettings()
            settings[keyPath: keyPath] = value
            settingsByConnection[connectionID] = settings
        })
    }

    private func tikTokPrivacyLabel(_ value: String) -> String {
        switch value {
        case "PUBLIC_TO_EVERYONE": "Everyone"
        case "MUTUAL_FOLLOW_FRIENDS": "Friends"
        case "FOLLOWER_OF_CREATOR": "Followers"
        case "SELF_ONLY": "Only me"
        default: value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var isTikTokPhotoPost: Bool {
        !selectedAssets.isEmpty && selectedAssets.allSatisfy { $0.mimeType.hasPrefix("image/") }
    }

    private func tikTokPrivacyOptions(for connectionID: String) -> [String] {
        let options = creatorInfoByConnection[connectionID]?.privacyLevelOptions ?? []
        guard settingsByConnection[connectionID]?.brandContent == true else { return options }
        return options.filter { ["PUBLIC_TO_EVERYONE", "MUTUAL_FOLLOW_FRIENDS"].contains($0) }
    }

    private func videoDurationSeconds(data: Data, fileExtension: String) async -> Double? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "mov" : fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            return duration.isFinite && duration > 0 ? duration : nil
        } catch {
            return nil
        }
    }

    private func requestWolfeyCaptions() async {
        do { wolfeySuggestions = try await WolfSocialAPIClient.shared.wolfey(task: "caption_variants", source: caption) }
        catch { model.errorMessage = error.localizedDescription }
    }
}

private struct WolfSocialCalendar: View {
    @ObservedObject var model: WolfSocialViewModel

    var body: some View {
        List(model.posts) { post in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(post.status.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(post.status == "failed" ? .red : .secondary)
                    Spacer()
                    Text(post.scheduledFor ?? "Immediate / draft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(post.title ?? post.caption).lineLimit(2)
                if let targets = post.socialPostTargets {
                    Text(targets.map { "\($0.platform.title): \($0.status)" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(targets.filter { $0.lastError?.isEmpty == false }) { target in
                        Label(target.lastError ?? "Publishing failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    if ["failed", "partial_failed"].contains(post.status) {
                        Button("Retry") { act(post, "retry") }
                    }
                    if ["draft", "scheduled", "publishing", "partial_failed", "failed"].contains(post.status) {
                        Button("Cancel", role: .destructive) { act(post, "cancel") }
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func act(_ post: WolfSocialPost, _ action: String) {
        Task {
            do {
                try await WolfSocialAPIClient.shared.postAction(postID: post.id, action: action)
                await model.refresh()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct WolfSocialInbox: View {
    @ObservedObject var model: WolfSocialViewModel
    @EnvironmentObject private var uiState: AppUIState
    @State private var replies: [String: String] = [:]
    var body: some View { List { if model.threads.isEmpty { ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right", description: Text("Facebook, Instagram and YouTube comments appear here. TikTok and LinkedIn inboxes and YouTube DMs are unavailable.")) } else { ForEach(model.threads) { thread in Section { ForEach(thread.socialInteractions ?? []) { interaction in Text(interaction.body).frame(maxWidth: .infinity, alignment: interaction.direction == "outbound" ? .trailing : .leading) }; if thread.platform != .tiktok && thread.platform != .linkedin { HStack { TextField("Approved reply", text: Binding(get: { replies[thread.id] ?? "" }, set: { replies[thread.id] = $0 })); Button("Wolfey") { Task { do { let source = thread.socialInteractions?.last(where: { $0.direction == "inbound" })?.body ?? ""; replies[thread.id] = try await WolfSocialAPIClient.shared.wolfey(task: "suggest_reply", source: source).first ?? "" } catch { model.errorMessage = error.localizedDescription } } }; Button("Send") { Task { do { try await WolfSocialAPIClient.shared.reply(threadID: thread.id, body: replies[thread.id] ?? ""); replies[thread.id] = ""; await model.refresh() } catch { model.errorMessage = error.localizedDescription } } } } }; if model.canCreateLead, let contact = thread.socialContacts, contact.salesLeadID == nil { Button("Create lead in Sales") { Task { do { _ = try await WolfSocialAPIClient.shared.createLead(contactID: contact.id); await model.refresh(); uiState.selectedTabIndex = 2 } catch { model.errorMessage = error.localizedDescription } } } } } header: { Text("\(thread.socialContacts?.displayName ?? thread.socialContacts?.username ?? "Social contact") · \(thread.platform.title)") } } } } }
}

private struct WolfSocialLibrary: View { @ObservedObject var model: WolfSocialViewModel; var body: some View { List(model.media) { asset in HStack { Image(systemName: asset.mimeType.hasPrefix("video/") ? "video.fill" : "photo.fill").foregroundStyle(.red); VStack(alignment: .leading) { Text(asset.originalName).lineLimit(1); Text(asset.mimeType).font(.caption).foregroundStyle(.secondary) } } } } }

private struct WolfSocialAnalyticsView: View { @ObservedObject var model: WolfSocialViewModel; var body: some View { ScrollView { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) { ForEach(model.analytics.totals.keys.sorted(), id: \.self) { key in VStack(alignment: .leading) { Text(key.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary); Text(Int(model.analytics.totals[key] ?? 0).formatted()).font(.title2.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)) } }.padding() } } }

private struct WolfSocialConnections: View {
    @ObservedObject var model: WolfSocialViewModel
    @ObservedObject var oauth: WolfSocialOAuthSession
    @State private var pendingDisconnect: WolfSocialConnection?

    var body: some View {
        List {
            ForEach(WolfSocialPlatform.allCases) { platform in
                Section(platform.title) {
                    ForEach(model.connections.filter { $0.platform == platform }) { connection in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(connection.accountName ?? platform.title, systemImage: platform.systemImage)
                                Spacer()
                                Text(connection.status)
                                    .font(.caption2.bold())
                                    .foregroundStyle(connection.status == "active" ? .green : .secondary)
                            }
                            if let warning = connection.lastError, !warning.isEmpty {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if platform == .linkedin {
                                Text(connection.accountType == "organization"
                                     ? "Company Page · \(connection.pageRole == "CONTENT_ADMIN" ? "Content admin verified" : "Administrator verified")"
                                     : "Personal profile · Share on LinkedIn")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Disconnect", role: .destructive) {
                                pendingDisconnect = connection
                            }
                        }
                    }
                    if model.providerAvailability[platform.rawValue]?.configured == false {
                        Label(model.providerAvailability[platform.rawValue]?.message ?? "Provider setup is required.", systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        let platformConnections = model.connections.filter { $0.platform == platform }
                        let hasExpiredConnection = platformConnections.contains { $0.status == "expired" || $0.status == "revoked" || $0.status == "error" }
                        Button(hasExpiredConnection ? "Reconnect \(platform.title)" : "Connect \(platformConnections.isEmpty ? platform.title : "another account")") {
                            oauth.connect(platform)
                        }
                        .disabled(oauth.isConnecting)
                    }
                }
            }
            Section {
                Text("Swipe a connected account to disconnect it. Facebook supports Pages. Instagram requires a professional account. LinkedIn Company Pages require Community Management approval. TikTok and LinkedIn inboxes and YouTube DMs are unavailable through their standard APIs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Disconnect \(pendingDisconnect?.accountName ?? pendingDisconnect?.platform.title ?? "account")?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let connection = pendingDisconnect else { return }
                pendingDisconnect = nil
                Task { await model.disconnect(connection) }
            }
            Button("Cancel", role: .cancel) { pendingDisconnect = nil }
        } message: {
            Text("Scheduled posts using this account will no longer be able to publish.")
        }
    }
}
