import ActivityKit
import SwiftUI
import WidgetKit

struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionLiveActivityAttributes.self) { context in
            SessionLockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("FLYRLogoWide")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 20)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Doors knocked")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Time")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        if context.state.isPaused {
                            Text("Paused")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        } else {
                            Text(timerInterval: context.state.startedAt...Date(), countsDown: false)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                }
            } compactLeading: {
                Text("\(context.state.completedCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text("FLYR")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Text("\(context.state.completedCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .keylineTint(.red)
        }
    }
}

private struct SessionLockScreenView: View {
    let context: ActivityViewContext<SessionLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image("FLYRLogoWide")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 36)

            Spacer(minLength: 0)

            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Text("\(context.state.completedCount)")
                        .font(.title2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("doors")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                SessionMetricInline(
                    value: context.state.isPaused ? "Paused" : nil,
                    timerStart: context.state.startedAt,
                    isPaused: context.state.isPaused
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct SessionMetricInline: View {
    var value: String?
    var timerStart: Date? = nil
    var isPaused = false

    var body: some View {
        if let value {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        } else if let timerStart, !isPaused {
            Text(timerInterval: timerStart...Date(), countsDown: false)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
