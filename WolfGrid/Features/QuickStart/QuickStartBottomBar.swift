import SwiftUI

struct QuickStartBottomBar: View {
    let isStartingDoor: Bool
    let isStartingFlyers: Bool
    let onStartDoorKnocking: () -> Void
    let onStartFlyers: () -> Void

    private var isBusy: Bool {
        isStartingDoor || isStartingFlyers
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                onStartDoorKnocking()
            } label: {
                HStack {
                    if isStartingDoor {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text("Start Door Knocking")
                        .font(.flyrSubheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .disabled(isBusy)

            Button {
                onStartFlyers()
            } label: {
                HStack {
                    if isStartingFlyers {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.red)
                    }
                    Text("Start Flyers")
                        .font(.flyrSubheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundColor(.red)
                .overlay(
                    Capsule().stroke(Color.red, lineWidth: 1.5)
                )
            }
            .disabled(isBusy)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .background(.ultraThinMaterial)
    }
}
