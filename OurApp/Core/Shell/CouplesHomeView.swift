import SwiftUI

/// The themed couples home (P4, layout per P8): moonlit background, the two of
/// us in the top corners, the day-counter hero in the middle, and the launcher
/// rail on the trailing edge. DEBUG launch arguments `-openDrawer` /
/// `-openSettings` exist solely so headless screenshot verification can reach
/// those states (simctl can't tap).
struct CouplesHomeView: View {
    let modules: [ModuleDescriptor]

    @State private var identity = CoupleIdentityStore()
    @State private var tilt = TiltModel()
    @State private var openModule: ModuleDescriptor?
    @State private var showSettings = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            DreamyBackground(parallax: tilt.offset)

            VStack(spacing: 0) {
                PartnerAvatarsView(identity: identity)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .offset(x: tilt.offset.width * 0.4, y: tilt.offset.height * 0.4)

                Spacer()

                VStack(spacing: 18) {
                    Text("💞")
                        .font(.system(size: 30))
                        .scaleEffect(pulse ? 1.15 : 0.95)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)

                    if let anniversary = identity.anniversary {
                        TogetherCounterView(anniversary: anniversary)
                    } else {
                        Button {
                            showSettings = true
                        } label: {
                            Label {
                                Text("Set your anniversary")
                            } icon: {
                                Image(systemName: "heart.circle.fill")
                            }
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .glassCard(cornerRadius: 22)
                    }

                    if identity.nameOne.isEmpty && identity.nameTwo.isEmpty {
                        Button {
                            showSettings = true
                        } label: {
                            Text("Add your names")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()
                Spacer() // hero sits slightly above center, like the reference
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Lower-right, thumb reach; the tile column grows upward and stays
            // clear of the centered hero.
            ModuleLauncherRail(
                modules: modules,
                openModule: $openModule,
                startsOpen: launchArguments.contains("-openDrawer")
            )
            .padding(.bottom, 96)
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                Haptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
            .glassCard(cornerRadius: 22)
            .padding(.leading, 16)
            .padding(.bottom, 8)
            .accessibilityLabel(Text("Our details"))
        }
        .fullScreenCover(item: $openModule) { module in
            ModuleHostView(module: module)
        }
        .sheet(isPresented: $showSettings) {
            CoupleSettingsSheet(identity: identity)
        }
        .onAppear {
            pulse = true
            tilt.start()
            if launchArguments.contains("-openSettings") { showSettings = true }
        }
        .onDisappear { tilt.stop() }
        .onChange(of: openModule == nil && !showSettings) { _, homeVisible in
            // The home is the root view, so onDisappear never fires in normal
            // use — bracket tilt by cover/sheet visibility instead.
            if homeVisible { tilt.start() } else { tilt.stop() }
        }
    }

    private var launchArguments: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }
}

#Preview {
    CouplesHomeView(modules: [FoodDecisionModule.descriptor])
}
