import SwiftUI

/// Main QR Workflow view with 4-tab bottom navigation
struct QRWorkflowView: View {
    @State private var selectedTab: QRWorkflowTab = .landingPages
    
    enum QRWorkflowTab: Int {
        case landingPages = 0
        case createQR = 1
        case print = 2
        case moreTools = 3
        
        var title: String {
            switch self {
            case .landingPages: return "Landing Pages"
            case .createQR: return "Create QR"
            case .print: return "Print"
            case .moreTools: return "More Tools"
            }
        }
        
        var icon: String {
            switch self {
            case .landingPages: return "doc.text.fill"
            case .createQR: return "qrcode"
            case .print: return "printer.fill"
            case .moreTools: return "ellipsis.circle.fill"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LandingPagesView()
                    .navigationTitle("Landing Pages")
            }
            .tag(QRWorkflowTab.landingPages)
            .tabItem {
                Label("Landing Pages", systemImage: QRWorkflowTab.landingPages.icon)
            }
            
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

