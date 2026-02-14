import SwiftUI

/// Main QR Workflow view with 3-tab bottom navigation
struct QRWorkflowView: View {
    @State private var selectedTab: QRWorkflowTab = .createQR
    
    enum QRWorkflowTab: Int {
        case createQR = 0
        case print = 1
        case moreTools = 2
        
        var title: String {
            switch self {
            case .createQR: return "Create QR"
            case .print: return "Print"
            case .moreTools: return "More Tools"
            }
        }
        
        var icon: String {
            switch self {
            case .createQR: return "qrcode"
            case .print: return "printer.fill"
            case .moreTools: return "ellipsis.circle.fill"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CreateQRView()
                    .navigationTitle("Create QR Code")
            }
            .tag(QRWorkflowTab.createQR)
            .tabItem {
                Label("Create QR", systemImage: QRWorkflowTab.createQR.icon)
            }
            
            NavigationStack {
                PrintQRView(qrCodeId: nil)
                    .navigationTitle("Print & Export")
            }
            .tag(QRWorkflowTab.print)
            .tabItem {
                Label("Print", systemImage: QRWorkflowTab.print.icon)
            }
            
            NavigationStack {
                MoreToolsView()
                    .navigationTitle("More Tools")
            }
            .tag(QRWorkflowTab.moreTools)
            .tabItem {
                Label("More Tools", systemImage: QRWorkflowTab.moreTools.icon)
            }
        }
    }
}

