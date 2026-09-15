import SwiftUI

/// Home/Den artwork. The separate RealityKit renderer remains available to map scenes.
struct WolfyPortraitView: View {
    let xp: Int?
    var previewStage: Int? = nil
    var celebrationID: String? = nil
    var resting = false
    var suspended = false
    var equipment: [String:String] = [:]
    var onTap: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var reaction = 0
    @State private var bounced = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var stage: Int { min(5, max(1, previewStage ?? WolfyProgression.growthStage(xp: xp ?? 0))) }
    private var animate: Bool { visible && scenePhase == .active && !reduceMotion && !lowPower && !resting && !suspended }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animate)) { context in
            let breath = animate ? (sin(context.date.timeIntervalSinceReferenceDate * 1.5) + 1) / 2 : 0
            GeometryReader { geometry in
                let side = min(geometry.size.width,geometry.size.height)
                WolfyPortraitComposition(stage:stage,equipment:equipment)
                .frame(width:side,height:side)
                .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
                .id(stage)
                .transition(.opacity)
                .scaleEffect(x: 1 + breath * 0.003, y: 1 + breath * 0.008, anchor: .bottom)
                .offset(y: bounced && animate ? -6 : 0)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: stage)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { reaction += 1; onTap?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wolfy, growth stage \(stage) of 5")
        .accessibilityHint(onTap == nil ? "Double tap to greet Wolfy" : "Double tap to visit Wolfy's Den")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { reaction += 1; onTap?() }
        .onAppear { visible = true }
        .onDisappear { visible = false; bounced = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: celebrationID) { _, value in if value != nil { reaction += 1 } }
        .task(id: reaction) {
            guard reaction > 0, animate else { return }
            withAnimation(.easeOut(duration: 0.18)) { bounced = true }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { bounced = false; return }
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { bounced = false }
        }
    }
}
