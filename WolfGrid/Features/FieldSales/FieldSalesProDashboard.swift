import SwiftUI

struct FieldSalesProDashboard: View {
    let workspace: UUID; let data: FieldSalesSnapshot; let initial: [String:String]
    @State private var recording = false
    @State private var openedInitial = false
    @State private var savedID: UUID?
    var body: some View {
        VStack(spacing: 0) {
            if let savedID { NavigationLink("Sale saved · Open sale") { FieldSalesRecordView(sale: savedID) }.font(.subheadline).padding(10) }
            FieldSalesReportView(teamInitially: data.capabilities?["team_details"] == true)
        }.navigationTitle("Sales")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Mark as sold") { recording = true } }
            ToolbarItem(placement: .secondaryAction) {
                Menu("Sales actions") {
                    NavigationLink("Pipeline & follow-ups") { FieldSalesPipelineRootView() }
                    NavigationLink("Goals & pace") { FieldSalesGoalsView() }
                    NavigationLink("Leaderboards") { FieldSalesLeaderboardView() }
                    if data.role == "owner" || data.role == "admin" { NavigationLink("Sales settings") { Form { FieldSalesSettings(data:data,workspace:workspace) } } }
                }
            }
        }
        .onAppear { if !openedInitial { openedInitial = true; recording = !initial.isEmpty } }
        .sheet(isPresented: $recording) { NavigationStack { FieldSalesMarkSoldView(workspace:workspace,initial:initial) { id in savedID = id; recording = false } }.presentationDetents([.large]).presentationDragIndicator(.visible) }
    }
}
