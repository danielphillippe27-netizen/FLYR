import SwiftUI

struct FarmTouchPlannerView: View {
    @StateObject private var viewModel: FarmTouchPlannerViewModel
    @State private var showAddTouch = false
    @State private var selectedMonth: String?
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
        _viewModel = StateObject(wrappedValue: FarmTouchPlannerViewModel(farmId: farmId))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(viewModel.sortedMonths, id: \.self) { month in
                    MonthSection(
                        month: month,
                        touches: viewModel.touchesForMonth(month),
                        viewModel: viewModel
                    )
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
    }
}

struct MonthSection: View {
    let month: String
    let touches: [FarmTouch]
    let viewModel: FarmTouchPlannerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(month)
                .font(.flyrHeadline)
                .padding(.horizontal, 16)
            
            ForEach(touches) { touch in
                TouchCard(touch: touch, viewModel: viewModel)
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct TouchCard: View {
    let touch: FarmTouch
    let viewModel: FarmTouchPlannerViewModel
    
    var body: some View {
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
            
            if touch.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
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



