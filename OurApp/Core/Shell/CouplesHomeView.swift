import SwiftUI

/// The themed couples home (decision P4): dreamy background, the two of us,
/// the together counter, and the launcher drawer. DEBUG launch arguments
/// `-openDrawer` / `-openSettings` exist solely so headless screenshot
/// verification can reach those states (simctl can't tap).
struct CouplesHomeView: View {
    let modules: [ModuleDescriptor]

    @State private var identity = CoupleIdentityStore()
    @State private var tilt = TiltModel()
    @State private var openModule: ModuleDescriptor?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            DreamyBackground(parallax: tilt.offset)

            VStack(spacing: 26) {
                Spacer(minLength: 70)
                PartnerAvatarsView(identity: identity)
                    .offset(x: tilt.offset.width * 0.4, y: tilt.offset.height * 0.4)

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

                Spacer()
                ModuleLauncherDrawer(
                    modules: modules,
                    openModule: $openModule,
                    startsOpen: launchArguments.contains("-openDrawer")
                )
            }
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(11)
            }
            .glassCard(cornerRadius: 22)
            .padding(.trailing, 16)
            .accessibilityLabel(Text("Our details"))
        }
        .fullScreenCover(item: $openModule) { module in
            ModuleHostView(module: module)
        }
        .sheet(isPresented: $showSettings) {
            CoupleSettingsSheet(identity: identity)
        }
        .onAppear {
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
