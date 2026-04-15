import SwiftUI

struct FarmTouchPlannerView: View {
    @StateObject private var viewModel: FarmTouchPlannerViewModel
    @State private var showAddTouch = false
    var onStartSession: ((FarmExecutionContext) -> Void)?
    
    let farmId: UUID
    
    init(farmId: UUID, onStartSession: ((FarmExecutionContext) -> Void)? = nil) {
        self.farmId = farmId
        self.onStartSession = onStartSession
        _viewModel = StateObject(wrappedValue: FarmTouchPlannerViewModel(farmId: farmId))
    }
    
    var body: some View {
        ScrollView {
            Group {
                if viewModel.isLoading && viewModel.touches.isEmpty {
                    ProgressView("Loading plan...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.sortedMonths.isEmpty {
                    ContentUnavailableView(
                        "No Farm Plan Yet",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Touches created in FLYR-PRO will show up here, and you can also add or complete them from iOS.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(viewModel.sortedMonths, id: \.self) { month in
                            MonthSection(
                                month: month,
                                touches: viewModel.touchesForMonth(month),
                                viewModel: viewModel,
                                onStartSession: onStartSession
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Touch Planner")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddTouch = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddTouch) {
            AddTouchView(viewModel: viewModel)
        }
        .task {
            await viewModel.loadTouches()
        }
        .refreshable {
            await viewModel.loadTouches()
        }
    }
}

struct MonthSection: View {
    let month: String
    let touches: [FarmTouch]
    let viewModel: FarmTouchPlannerViewModel
    let onStartSession: ((FarmExecutionContext) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(month)
                .font(.flyrHeadline)
                .padding(.horizontal, 16)
            
            ForEach(touches) { touch in
                TouchCard(
                    touch: touch,
                    viewModel: viewModel,
                    onStartSession: onStartSession
                )
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct TouchCard: View {
    let touch: FarmTouch
    let viewModel: FarmTouchPlannerViewModel
    let onStartSession: ((FarmExecutionContext) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: touch.type.iconName)
                    .foregroundColor(colorForType(touch.type))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(touch.title)
                        .font(.flyrSubheadline)
                    Text(touch.date, style: .date)
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.markComplete(touch, completed: !touch.completed)
                    }
                } label: {
                    Image(systemName: touch.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(touch.completed ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            if touch.campaignId != nil, !touch.completed {
                Button {
                    Task {
                        guard let context = await viewModel.executionContext(for: touch) else { return }
                        await MainActor.run {
                            onStartSession?(context)
                        }
                    }
                } label: {
                    HStack {
                        Text(touch.type == .flyer ? "Start planned flyer session" : "Start planned session")
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else if touch.campaignId == nil && !touch.completed {
                Text("Attach a campaign to this touch in FLYR-PRO to run it from iOS.")
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .overlay(alignment: .leading) {
            if touch.completed {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1.5)
            }
        }
    }
    
    private func colorForType(_ type: FarmTouchType) -> Color {
        switch type {
        case .flyer: return .blue
        case .doorKnock: return .green
        case .event: return .flyrPrimary
        case .newsletter: return .purple
        case .ad: return .yellow
        case .custom: return .gray
        }
    }
}

struct AddTouchView: View {
    @ObservedObject var viewModel: FarmTouchPlannerViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var date = Date()
    @State private var type: FarmTouchType = .flyer
    @State private var title = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Touch Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("Type", selection: $type) {
                        ForEach(FarmTouchType.allCases) { touchType in
                            Text(touchType.displayName).tag(touchType)
                        }
                    }
                    
                    TextField("Title", text: $title)
                    TextField("Notes (Optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add Touch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await viewModel.addTouch(
                                date: date,
                                type: type,
                                title: title.isEmpty ? type.displayName : title,
                                notes: notes.isEmpty ? nil : notes
                            )
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FarmTouchPlannerView(farmId: UUID())
    }
}
