import SwiftUI

struct WolfyCoachView: View {
    @ObservedObject var coach: WolfyCoachStore
    let user: UUID
    let workspace: UUID
    @State private var question = ""
    @FocusState private var focused: Bool
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Your coach in the Den", systemImage: "sparkles").font(.title2.bold())
                    Text("Wolfy uses your synced doors, conversations, leads, appointments and personal goals. AI can make mistakes; your activity cards show the verified numbers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Your question and recent conversation are sent to OpenAI with an activity summary. Contact names and notes aren't included automatically. Use Clear to erase this conversation. Switching accounts or workspaces starts a new conversation.")
                        .font(.caption).foregroundStyle(.secondary)
                    if coach.messages.isEmpty {
                        ForEach(["What should I focus on today?", "Help me handle ‘not interested’", "How can I improve my door opener?"], id: \.self) { prompt in
                            Button(prompt) { send(prompt) }.buttonStyle(.bordered).disabled(coach.sending)
                        }
                    }
                    ForEach(coach.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == "user" ? "You" : message.label ?? "Wolfy").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(message.content).textSelection(.enabled)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == "user" ? Color.orange.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if coach.sending { ProgressView("Wolfy is thinking…") }
                    if let error = coach.error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        if !coach.messages.isEmpty {
                            Button("Retry question") { Task { await coach.retry(user: user, workspace: workspace) } }.disabled(coach.sending)
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
                        .disabled(coach.sending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(.regularMaterial)
            }
        }.navigationTitle("Ask Wolfy").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Clear") { coach.clear() }.disabled(coach.sending) }
    }
    private func send(_ value: String) {
        question = ""; focused = false
        Task { await coach.ask(value, user: user, workspace: workspace) }
    }
}
