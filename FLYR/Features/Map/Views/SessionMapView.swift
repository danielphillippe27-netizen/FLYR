import SwiftUI

struct SessionMapView: View {
    @ObservedObject var manager = SessionManager.shared
    
    var body: some View {
        ZStack {
            SessionMapboxViewRepresentable(
                coordinates: manager.pathCoordinates,
                currentLocation: manager.currentLocation,
                currentHeading: manager.currentHeading
            )
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                    .frame(height: 60)
                SessionStatsView()
                Spacer()
                EndSessionButton()
            }
        }
    }
}

