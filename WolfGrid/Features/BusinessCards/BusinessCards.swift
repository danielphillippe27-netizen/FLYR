import PhotosUI
import SwiftUI
import Combine
import MessageUI
import Supabase
import CoreImage.CIFilterBuiltins

struct BusinessCardContent: Codable, Equatable {
    struct Social: Codable, Equatable, Identifiable { var platform: String; var url: String; var id: String { platform } }
    struct Theme: Codable, Equatable { var header = "#14161B"; var accent = "#D9233B"; var background = "#FFFFFF" }
    var theme: Theme? = nil
    var companyLogo: String? = nil
    var name = ""; var title = ""; var company = ""; var bio = ""; var phone = ""; var email = ""; var photo = ""; var reviewUrl = ""
    var socials: [Social] = []
    var hasDetails: Bool {
        ([name, title, company, bio, phone, email, photo, reviewUrl, companyLogo ?? ""] + socials.map(\.url))
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
struct BusinessCardProfile: Codable { let id: UUID; var content: BusinessCardContent; var published: Bool }
struct BusinessCardProfileResponse: Codable { var profile: BusinessCardProfile? }
struct BusinessCardShare: Codable, Identifiable { let id: UUID; let url: String; let message: String; let phone: String }
struct BusinessCardActivityResponse: Codable {
    struct Share: Codable, Identifiable {
        struct Event: Codable, Identifiable { let id: UUID; let event_type: String; let detail: String?; let created_at: String }
        let id: UUID; let created_at: String; let revoked_at: String?; let card_events: [Event]
    }
    let shares: [Share]
}
@MainActor enum BusinessCardAPI {
    static func request<T: Decodable>(_ path: String, body: [String: Any]? = nil, workspaceID: UUID? = nil, expectedUserID: UUID? = nil) async throws -> T {
        guard let workspace = workspaceID ?? WorkspaceContext.shared.workspaceId else { throw failure("Select a workspace first") }
        let session = try await SupabaseManager.shared.client.auth.session
        if let expectedUserID, session.user.id != expectedUserID { throw failure("Sign in to the original account to sync this card") }
        var parts = URLComponents(string: "https://wolfgrid.app/api/cards/\(path)")!
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "workspaceId", value: workspace.uuidString)]
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if var body { body["workspaceId"] = workspace.uuidString; request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw failure(payload?["error"] as? String ?? "Business card request failed. Please retry.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func uploadImage(_ data: Data, kind: String) async throws -> String {
        guard let workspace = WorkspaceContext.shared.workspaceId else { throw failure("Select a workspace first") }
        guard data.count <= 3 * 1024 * 1024 else { throw failure("Choose a smaller image") }
        let session = try await SupabaseManager.shared.client.auth.session
        var parts = URLComponents(string: "https://wolfgrid.app/api/cards/images")!
        parts.queryItems = [URLQueryItem(name:"workspaceId",value:workspace.uuidString),URLQueryItem(name:"kind",value:kind)]
        var request=URLRequest(url:parts.url!);request.httpMethod="POST";request.setValue("Bearer \(session.accessToken)",forHTTPHeaderField:"Authorization");request.setValue(kind == "companyLogo" ? "image/png" : "image/jpeg",forHTTPHeaderField:"Content-Type");request.httpBody=data
        let (responseData,response)=try await URLSession.shared.data(for:request)
        let payload=(try? JSONSerialization.jsonObject(with:responseData)) as? [String:Any]
        guard let response=response as? HTTPURLResponse,(200...299).contains(response.statusCode),let url=payload?["url"] as? String else { throw failure(payload?["error"] as? String ?? "Image upload failed. Please retry.") }
        return url
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "BusinessCards", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    struct OK: Decodable { let ok: Bool }
    static func composer(_ id: UUID, type: String) async { let _: OK? = try? await request("shares/\(id.uuidString)/composer", body: ["type": type, "eventId": UUID().uuidString]) }
}
struct BusinessCardEditorView: View {
    @StateObject private var editor = BusinessCardEditorStore.current()
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: String? = nil
    @State private var selectedImage: PhotosPickerItem? = nil
    @State private var pendingImageKind: String?
    @State private var imageKind = "photo"
    @State private var showImagePicker = false
    @State private var uploadingImage = false
    @State private var imageError: String? = nil
    @State private var imageToCrop: BusinessCardCropSelection?
    @State private var preparingImage = false
    private var theme: BusinessCardContent.Theme { editor.card.theme ?? .init() }
    private var background: Color { Color(cardHex: theme.background) }
    private var foreground: Color { cardInk(theme.background) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tap your card to edit").font(.headline)
                Text("Changes save automatically. Preview interactions aren’t tracked.").font(.caption).foregroundStyle(.secondary)
                if preparingImage { ProgressView("Opening image…") }
                if uploadingImage { ProgressView("Uploading image…") }
                saveStatus
                VStack(alignment: .leading, spacing: 0) {
                    Button { editing = "Company" } label: {
                        Color(cardHex: theme.header)
                            .aspectRatio(3, contentMode: .fit)
                            .overlay {
                                GeometryReader { geometry in
                                    if let logo = editor.card.companyLogo, !logo.isEmpty, let url = URL(string: logo) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Text(editor.card.company).foregroundStyle(cardInk(theme.header))
                                        }
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped()
                                    } else {
                                        Text(editor.card.company.isEmpty ? "Add company logo  ✎" : editor.card.company)
                                            .font(.title2.bold()).foregroundStyle(cardInk(theme.header))
                                            .padding(22)
                                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                                    }
                                }
                            }
                            .clipped()
                    }.buttonStyle(.plain).padding(.bottom,40)
                    .overlay(alignment: .bottomLeading) {
                        Button { editing = "Photo" } label: {
                            if let url = URL(string: editor.card.photo), !editor.card.photo.isEmpty {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }.frame(width: 80, height: 80).clipShape(Circle())
                            } else { Text("Photo +").font(.caption.bold()).frame(width: 80, height: 80).background(foreground.opacity(0.08), in: Circle()) }
                        }.buttonStyle(.plain).background(background, in: Circle()).overlay(Circle().strokeBorder(background,lineWidth:3)).padding(.leading,22)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Button { editing = "Identity" } label: {
                            VStack(alignment: .leading, spacing: 6) { Text(editor.card.name.isEmpty ? "Your name  ✎" : editor.card.name).font(.title.bold()); Text(editor.card.title.isEmpty ? "Add your title" : editor.card.title); Text(editor.card.company.isEmpty ? "Your company" : editor.card.company).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { editing = "Colours" } label: { Label("Save Contact", systemImage: "arrow.down.to.line").font(.headline).frame(maxWidth: .infinity).padding(16).background(Color(cardHex: theme.accent), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(cardInk(theme.accent)) }.buttonStyle(.plain)
                        Button { editing = "Social links" } label: {
                            VStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    ForEach(Array((editor.card.socials.filter { !$0.url.isEmpty }.isEmpty ? Array(editor.card.socials.prefix(4)) : editor.card.socials))) { social in
                                        VStack(spacing: 5) {
                                            if social.platform == "Website" { Image(systemName: "globe").frame(width: 32,height: 32) } else { Image("CardSocial" + social.platform.lowercased()).resizable().scaledToFit().frame(width: 24, height: 24).padding(5).background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8)) }
                                            Text(social.platform).font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.7)
                                        }.frame(maxWidth: .infinity)
                                    }
                                }
                                Text("Edit social links").font(.caption)
                            }
                        }.buttonStyle(.plain)
                        Button { editing = "Contact" } label: { HStack { Label("Call",systemImage: "phone"); Spacer(); Label("Text",systemImage:"message"); Spacer(); Label("Email",systemImage:"envelope") }.font(.caption).padding(.vertical, 12) }.buttonStyle(.plain)
                        Button { editing = "About" } label: { VStack(alignment: .leading,spacing: 8) { Text("About me  ✎").font(.headline); Text(editor.card.bio.isEmpty ? "Tell people a little about yourself." : editor.card.bio).font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                        Button(editor.card.reviewUrl.isEmpty ? "Add review link" : "Read or leave a review") { editing = "Review" }.font(.caption)
                    }.padding(22)
                }.disabled(!editor.loaded).foregroundStyle(foreground).background(background).clipShape(RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.secondary.opacity(0.15)))
                Button { editing = "Colours" } label: { Label("Appearance · edit colours", systemImage: "paintpalette").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Text("Your card publishes automatically when you save your details.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.navigationTitle("My Business Card")
        .task {
            await editor.load()
            if editor.loaded { await PushRegistrationService.shared.requestCampaignReadyPermissionAndRegister() }
        }
        .onDisappear { editor.flush() }
        .onChange(of: scenePhase) { _, _ in editor.flush() }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImage, matching: .images)
        .onChange(of: selectedImage) { _, item in
            guard let item else { return }
            let kind = imageKind
            preparingImage = true
            Task {
                defer { preparingImage = false; selectedImage = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let source = UIImage(data: data) else {
                        throw BusinessCardAPI.failure("Unable to open this photo")
                    }
                    imageToCrop = BusinessCardCropSelection(image: source, kind: kind)
                } catch { imageError = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { imageToCrop != nil && !showImagePicker },
            set: { if !$0 { imageToCrop = nil } }
        )) {
            if let selection = imageToCrop {
                BusinessCardImageCropView(selection: selection) { image in
                    imageToCrop = nil
                    uploadingImage = true
                    Task {
                        defer { uploadingImage = false }
                        do {
                            guard let encoded = selection.kind == "companyLogo" ? image.pngData() : image.jpegData(compressionQuality: 0.85) else {
                                throw BusinessCardAPI.failure("Unable to prepare this photo")
                            }
                            let url = try await BusinessCardAPI.uploadImage(encoded, kind: selection.kind)
                            if selection.kind == "companyLogo" { editor.card.companyLogo = url } else { editor.card.photo = url }
                            editor.flush()
                        } catch { imageError = error.localizedDescription }
                    }
                }
            }
        }
        .alert("Image upload", isPresented: Binding(get:{imageError != nil},set:{if !$0 {imageError=nil}})) { Button("OK") {imageError=nil} } message: { Text(imageError ?? "") }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), onDismiss: { editor.flush(); if let kind = pendingImageKind { imageKind=kind; pendingImageKind=nil; showImagePicker=true } }) {
            NavigationStack { Form { Section { saveStatus }; editingFields }.navigationTitle(editing ?? "Edit").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = nil } }; if editing == "Social links" { ToolbarItem(placement: .primaryAction) { EditButton() } } } }.presentationDetents([.medium,.large])
        }
    }
    @ViewBuilder private var editingFields: some View {
        switch editing {
        case "Company": imagePickerButton("Upload company logo", kind:"companyLogo"); field("Company", \.company); TextField("Company logo https:// URL", text: Binding(get: { editor.card.companyLogo ?? "" }, set: { editor.card.companyLogo = $0 })).textInputAutocapitalization(.never).keyboardType(.URL)
        case "Photo": imagePickerButton("Choose profile photo", kind:"photo"); field("Photo https:// URL (optional)", \.photo)
        case "Identity": field("Name", \.name); field("Title", \.title); field("Company", \.company)
        case "Contact": field("Phone", \.phone); field("Email", \.email)
        case "About": TextField("About me",text:$editor.card.bio,axis:.vertical).lineLimit(4...10)
        case "Review": field("Review https:// URL", \.reviewUrl)
        case "Social links":
            Text("Enter your username or paste a full profile link. Changes save automatically.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($editor.card.socials) { $social in
                VStack(alignment: .leading, spacing: 6) {
                    Text(social.platform).font(.subheadline.weight(.semibold))
                    if let prefix = BusinessCardSocialLink.prefix(for: social.platform) {
                        let value = BusinessCardSocialLink.username(from: social.url, platform: social.platform)
                        if !value.contains("://") {
                            Text(prefix).font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Username", text: Binding(
                            get: { BusinessCardSocialLink.username(from: social.url, platform: social.platform) },
                            set: { social.url = BusinessCardSocialLink.url(from: $0, platform: social.platform) }
                        ))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityLabel(social.platform + " username or profile link")
                    } else {
                        TextField("https://yourwebsite.com", text: $social.url)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityLabel("Website URL")
                    }
                }.padding(.vertical, 4)
            }.onMove { editor.card.socials.move(fromOffsets: $0, toOffset: $1) }
        case "Colours":
            ColorPicker("Header", selection: colorBinding(\.header), supportsOpacity: false)
            ColorPicker("Save Contact button", selection: colorBinding(\.accent), supportsOpacity: false)
            ColorPicker("Card background", selection: colorBinding(\.background), supportsOpacity: false)
            Text("Text adjusts automatically for contrast.").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
    private func imagePickerButton(_ title:String,kind:String)->some View {
        Button { pendingImageKind=kind;editing=nil } label: { Label(title,systemImage:"photo.on.rectangle") }.disabled(uploadingImage || preparingImage || !editor.loaded)
    }
    private func field(_ title: String, _ key: WritableKeyPath<BusinessCardContent,String>) -> some View { TextField(title,text:Binding(get: { editor.card[keyPath:key] },set: { editor.card[keyPath:key] = $0 })) }
    private func colorBinding(_ key: WritableKeyPath<BusinessCardContent.Theme,String>) -> Binding<Color> {
        Binding(get: { Color(cardHex: theme[keyPath:key]) }, set: { value in var t=theme; var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0; UIColor(value).getRed(&r,green:&g,blue:&b,alpha:&a);t[keyPath:key]=String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255));editor.card.theme=t })
    }
    @ViewBuilder private var saveStatus: some View {
        HStack {
            if editor.isSaving { ProgressView() }
            Text(editor.status).font(.caption).foregroundStyle(.secondary)
            if editor.canRetry { Button("Retry") { editor.flush() } }
        }
    }
}
private extension Color {
    init(cardHex: String) { let n=UInt64(cardHex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0xffffff;self.init(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255) }
}
private func cardInk(_ hex:String)->Color {
    let n=UInt64(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0xffffff
    func channel(_ shift:Int)->Double { let c=Double((n>>shift)&255)/255;return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
    return 0.2126*channel(16)+0.7152*channel(8)+0.0722*channel(0)>0.179 ? Color(cardHex:"#151719") : .white
}

enum BusinessCardRecipient {
    static func validPhone(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber).count
        return (7...15).contains(digits) && trimmed.range(of: "^[+0-9 ()-]+$", options: .regularExpression) != nil
    }
    static func validEmail(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

struct BusinessCardDeliveryStatus {
    let lastOpen: Date?
    let sent: Bool
    let interactionCount: Int

    init(shares: [BusinessCardActivityResponse.Share], localSentID: UUID? = nil) {
        let events = shares.filter { $0.revoked_at == nil }.flatMap(\.card_events)
        lastOpen = events.filter { $0.event_type == "qualified_open" }.compactMap { event in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: event.created_at) ?? ISO8601DateFormatter().date(from: event.created_at)
        }.max()
        sent = localSentID != nil || events.contains { $0.event_type == "composer_sent" }
        let interactions: Set<String> = ["call_clicked", "text_clicked", "email_clicked", "contact_downloaded", "social_clicked", "website_clicked", "review_clicked", "referral_started"]
        interactionCount = events.filter { interactions.contains($0.event_type) }.count
    }
}

struct BusinessCardSendView: View {
    var addressID: UUID? = nil
    var contactID: UUID? = nil
    var phone = ""
    var email = ""
    var saveLead: (() async throws -> UUID)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var share: BusinessCardShare?
    @State private var showOptions = false
    @State private var channel: Channel?
    @State private var pendingChannel: Channel?
    @State private var pendingKey = UUID()
    @State private var busy = false
    @State private var message = ""
    @State private var activity: [BusinessCardActivityResponse.Share] = []
    @State private var resolvedID: UUID?
    @State private var localSentID: UUID?
    @State private var linkStatus: String?
    private enum Channel: String, Identifiable { case text, email, qr; var id: String { rawValue } }
    private var canShare: Bool { BusinessCardRecipient.validPhone(phone) || BusinessCardRecipient.validEmail(email) }
    private var ink: Color { Color(cardHex: colorScheme == .dark ? "#E3D2FF" : "#6026A6") }
    private var status: BusinessCardDeliveryStatus { BusinessCardDeliveryStatus(shares: activity, localSentID: localSentID) }
    private var lastOpen: Date? { status.lastOpen }
    private var sent: Bool { status.sent }
    private var interactionCount: Int { status.interactionCount }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { message = ""; showOptions = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: lastOpen == nil ? "person.crop.rectangle" : "checkmark.circle.fill")
                        .frame(width: 20)
                    VStack(spacing: 4) {
                        Text(busy ? "Preparing card…" : lastOpen != nil ? "Business Card opened" : sent ? "Business Card sent" : linkStatus ?? "Send Business Card")
                            .font(.system(size: 17, weight: .semibold))
                        if let opened = lastOpen {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text("Viewed \(RelativeDateTimeFormatter().localizedString(for: opened, relativeTo: context.date)) · \(interactionCount) \(interactionCount == 1 ? "interaction" : "interactions")")
                                    .font(.caption)
                            }
                        } else if sent || linkStatus != nil {
                            Text("Not opened yet").font(.caption)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(cardHex: colorScheme == .dark ? "#352447" : "#EFE4FC"), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .trailing) {
                        if busy { ProgressView().tint(ink).padding(.trailing, 8) }
                    }
                }
                .foregroundStyle(ink)
                .opacity(canShare ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(busy || !canShare)
            .contextMenu {
                ForEach(activity.filter { $0.revoked_at == nil }.sorted { $0.created_at > $1.created_at }) { item in
                    Button("Revoke card link · \(item.created_at.prefix(10))", role: .destructive) {
                        Task {
                            do {
                                let _: BusinessCardAPI.OK = try await BusinessCardAPI.request("shares/\(item.id.uuidString)/revoke", body: [:])
                                if localSentID == item.id { localSentID = nil }
                                if share?.id == item.id { share = nil; linkStatus = nil; pendingKey = UUID() }
                                await refresh()
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $showOptions, onDismiss: {
            // Present the composer only after the options sheet has finished dismissing.
            if let next = pendingChannel { channel = next; pendingChannel = nil }
        }) {
            NavigationStack {
                VStack(spacing: 8) {
                    option("Text", icon: "message", enabled: BusinessCardRecipient.validPhone(phone)) { await prepare(.text) }
                    option("Email", icon: "envelope", enabled: BusinessCardRecipient.validEmail(email)) { await prepare(.email) }
                    option("QR Code", icon: "qrcode") { await prepare(.qr) }
                    option("Copy Link", icon: "link") { await prepare(nil) }
                    if busy { ProgressView("Preparing card…") }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(20)
                .navigationTitle("Send Business Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOptions = false }.disabled(busy) } }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(busy)
        }
        .sheet(item: $channel) { selected in
            if let share {
                switch selected {
                case .text:
                    BusinessCardComposer(share: share) { result in
                        complete(share, type: result == .sent ? "composer_sent" : result == .cancelled ? "composer_cancelled" : "composer_failed")
                    }
                case .email:
                    BusinessCardMailComposer(share: share, email: email.trimmingCharacters(in: .whitespacesAndNewlines)) { result in
                        complete(share, type: result == .sent ? "composer_sent" : result == .failed ? "composer_failed" : "composer_cancelled")
                    }
                case .qr:
                    NavigationStack {
                        VStack(spacing: 20) {
                            if let image = Self.qrImage(share.url) {
                                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 240, height: 240).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 16))
                            }
                            Text("Scan to open my business card").font(.headline)
                        }
                        .navigationTitle("Business Card")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { channel = nil } } }
                    }
                }
            }
        }
        .task(id: (contactID?.uuidString ?? "") + (addressID?.uuidString ?? "")) {
            resolvedID = contactID
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .businessCardActivityChanged)) { _ in Task { await refresh() } }
    }
    private func option(_ title: String, icon: String, enabled: Bool = true, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.disabled(busy || !enabled).tint(ink)
    }
    private func prepare(_ selected: Channel?) async {
        guard NetworkMonitor.shared.isOnline else { message = "Reconnect and let this lead sync before sending."; return }
        if selected == .text && !MFMessageComposeViewController.canSendText() { message = "Text messaging is unavailable on this device. Use QR Code or Copy Link."; return }
        if selected == .email && !MFMailComposeViewController.canSendMail() { message = "Set up Mail on this device, or use Copy Link."; return }
        busy = true; message = ""; defer { busy = false }
        do {
            let id: UUID
            if let saveLead { id = try await saveLead() } else if let contactID { id = contactID } else { throw BusinessCardAPI.failure("Save this lead first") }
            resolvedID = id
            try await BusinessCardEditorStore.current().prepareForSharing()
            var body: [String: Any] = ["contactId": id.uuidString, "idempotencyKey": pendingKey.uuidString]
            if let addressID { body["addressId"] = addressID.uuidString }
            let value: BusinessCardShare = try await BusinessCardAPI.request("shares", body: body)
            share = value
            if let selected {
                if selected == .qr { linkStatus = "Business Card QR ready" }
                pendingChannel = selected
            } else {
                UIPasteboard.general.string = value.url
                linkStatus = "Business Card link copied"
            }
            showOptions = false
            if selected == .text || selected == .email { await BusinessCardAPI.composer(value.id, type: "composer_opened") }
        } catch { message = error.localizedDescription }
    }
    private func complete(_ value: BusinessCardShare, type: String) {
        channel = nil
        if type == "composer_sent" { localSentID = value.id; pendingKey = UUID() }
        if type == "composer_failed" { message = "Your card could not be sent. Please try again." }
        Task { await BusinessCardAPI.composer(value.id, type: type); await refresh() }
    }
    private func refresh() async {
        guard let id = addressID ?? resolvedID else { return }
        let key = addressID != nil ? "addressId" : "contactId"
        if let response: BusinessCardActivityResponse = try? await BusinessCardAPI.request("activity?\(key)=\(id.uuidString)") {
            let previousOpen = lastOpen
            activity = response.shares
            if lastOpen != previousOpen {
                NotificationCenter.default.post(name: .businessCardEngagementChanged, object: nil)
            }
        }
    }
    private static func qrImage(_ url: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.utf8)
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent.applying(CGAffineTransform(scaleX: 10, y: 10))) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct BusinessCardMailComposer: UIViewControllerRepresentable {
    let share: BusinessCardShare
    let email: String
    let completion: (MFMailComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([email]); controller.setSubject("My business card")
        controller.setMessageBody(share.message, isHTML: false); controller.mailComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void
        init(_ completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { completion(error == nil ? result : .failed) }
    }
}

extension Notification.Name {
    static let businessCardActivityChanged = Notification.Name("businessCardActivityChanged")
    static let businessCardEngagementChanged = Notification.Name("businessCardEngagementChanged")
}
private struct BusinessCardComposer: UIViewControllerRepresentable {
    let share: BusinessCardShare; let completion: (MessageComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController { let controller = MFMessageComposeViewController(); controller.recipients = [share.phone]; controller.body = share.message; controller.messageComposeDelegate = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate { let completion: (MessageComposeResult) -> Void; init(_ completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }; func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { completion(result) } }
}

struct BusinessCardEngagement: Decodable {
    let address_id: UUID
    let building_id: String?
}
@MainActor final class BusinessCardEngagementStore: ObservableObject {
    @Published var rows: [BusinessCardEngagement] = []
    func observe(campaignID: String) async {
        rows = []
        guard UUID(uuidString: campaignID) != nil else { return }
        let client = SupabaseManager.shared.client
        let channel = client.realtimeV2.channel("card-map-\(campaignID)-\(UUID())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "card_property_engagement", filter: .eq("campaign_id", value: campaignID))
        let updateTask = Task {
            for await _ in changes {
                if Task.isCancelled { break }
                await refresh(campaignID)
                NotificationCenter.default.post(name: .businessCardActivityChanged, object: nil)
            }
        }
        let refreshTask = Task {
            for await _ in NotificationCenter.default.notifications(named: .businessCardEngagementChanged) {
                if Task.isCancelled { break }
                await refresh(campaignID)
            }
        }
        try? await channel.subscribeWithError()
        await refresh(campaignID)
        while !Task.isCancelled { do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { break }; await refresh(campaignID) }
        updateTask.cancel()
        refreshTask.cancel()
        await client.realtimeV2.removeChannel(channel)
    }
    private func refresh(_ campaignID: String) async {
        do { let result = try await SupabaseManager.shared.client.from("card_property_engagement").select("address_id,building_id").eq("campaign_id", value: campaignID).execute(); rows = try JSONDecoder().decode([BusinessCardEngagement].self, from: result.data) } catch { /* Reconcile on the next successful refresh; keep cached state while offline. */ }
    }
}
