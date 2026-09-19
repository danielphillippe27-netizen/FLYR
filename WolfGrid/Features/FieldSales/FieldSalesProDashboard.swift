import SwiftUI

struct FieldSalesProDashboard: View {
    private enum SalesSection: String, CaseIterable { case overview = "Overview"; case performance = "Performance"; case leaderboards = "Leaderboards" }
    let workspace: UUID; let data: FieldSalesSnapshot; let initial: [String:String]
    @State private var recording = false
    @State private var openedInitial = false
    @State private var savedID: UUID?
    @State private var section = SalesSection.overview
    @State private var entryContext: [String:String] = [:]
    var body: some View {
        VStack(spacing: 0) {
            if let savedID { NavigationLink("Sale saved · Open sale") { FieldSalesRecordView(sale: savedID) }.font(.subheadline).padding(10) }
            Picker("Sales view", selection: $section) { ForEach(SalesSection.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
            switch section {
            case .overview:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        FieldSalesCommissionHomeView(showsHeader: true)
                            .padding(18)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                        FieldSalesProHomeView()
                        HStack(spacing: 12) {
                            NavigationLink("Pipeline & follow-ups") { FieldSalesPipelineRootView() }
                            Spacer()
                            NavigationLink("Goals & pace") { FieldSalesGoalsView() }
                        }.font(.subheadline.weight(.medium))
                    }.padding()
                }.background(Color(uiColor: .systemGroupedBackground))
            case .performance:
                FieldSalesReportView(teamInitially: data.capabilities?["team_details"] == true)
            case .leaderboards:
                FieldSalesLeaderboardView()
            }
        }.navigationTitle("Sales")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Convert appointment") { entryContext = [:]; recording = true } }
            ToolbarItem(placement: .secondaryAction) {
                Menu("Sales actions") {
                    NavigationLink("Pipeline & follow-ups") { FieldSalesPipelineRootView() }
                    NavigationLink("Goals & pace") { FieldSalesGoalsView() }
                    NavigationLink("Leaderboards") { FieldSalesLeaderboardView() }
                    if data.role == "owner" || data.role == "admin" { NavigationLink("Sales settings") { Form { FieldSalesSettings(data:data,workspace:workspace) } } }
                }
            }
        }
        .onAppear { if !openedInitial { openedInitial = true; entryContext = initial; recording = !initial.isEmpty } }
        .sheet(isPresented: $recording) { NavigationStack { FieldSalesMarkSoldView(workspace:workspace,initial:entryContext) { id in savedID = id; entryContext = [:]; recording = false } }.presentationDetents([.large]).presentationDragIndicator(.visible) }
    }
}
