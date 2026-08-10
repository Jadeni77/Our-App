import SwiftUI

/// The themed couples home (P4, layout per P8) — now a hub (P16): moonlit
/// background, the two of us in the top corners, the day-counter hero in the
/// middle, and a row of topic tiles above the tab bar that push full
/// sub-pages. The module launcher lives on the Games tab (P11).
///
/// DEBUG launch arguments exist solely so headless screenshot verification can
/// reach a state simctl can't tap to: `-openSettings`, `-specialDates`,
/// `-dailyQuestion`, `-seedDailyQuestion`, `-memories`, `-seedMemories`, `-seedSpark`, `-seedSparkAtRisk`, `-sparkSheet`.
struct CouplesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var identity = CoupleIdentityStore()
    @State private var tilt = TiltModel()
    @State private var showSettings = false
    @State private var pulse = false
    @State private var path = NavigationPath()
    @State private var didHandleLaunchArguments = false

    /// The hero is hidden whenever something covers it — a pushed sub-page or
    /// the settings sheet. Pushing does NOT unmount Home, so without this the
    /// accelerometer would keep running behind a sub-page.
    private var heroCovered: Bool { showSettings || !path.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DreamyBackground(parallax: tilt.offset)

                VStack(spacing: 0) {
                    PartnerAvatarsView(identity: identity)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .offset(x: tilt.offset.width * 0.4, y: tilt.offset.height * 0.4)

                    Spacer()

                    VStack(spacing: 18) {
                        PairedHeartsView(size: 38)
                            .scaleEffect(pulse ? 1.15 : 0.95)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)

                        HomeCounter {
                            Haptics.tap()
                            path.append(HubRoute(entryID: "special-dates"))
                        }

                        // 火花 (H25). Inside the geometry group deliberately —
                        // it changes the hero's geometry, which is exactly what
                        // the group is here to absorb.
                        SparkPill()

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
                    // Non-obvious, and it bites hard: the 💞 carries a
                    // `repeatForever` animation, and an *active* repeating
                    // animation also sweeps in any geometry change its view
                    // receives. Adding the hub row and NavigationStack made the
                    // hero's frame settle one beat after first layout, so the
                    // hearts began oscillating between the old and new position
                    // forever. `geometryGroup` resolves this subtree's position
                    // before handing it to children, so only the scale pulses.
                    .geometryGroup()

                    Spacer()

                    // The hub. The gear rides just above it on a quick-action
                    // line — it used to float at the bottom-left, where the
                    // panel now sits.
                    VStack(spacing: 10) {
                        HStack {
                            settingsButton
                            Spacer()
                        }
                        HubEntryRow(entries: HubCatalog.entries)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
            }
            .toolbar(.hidden, for: .navigationBar)   // the hero is Home's top
            .navigationDestination(for: HubRoute.self) { destination(for: $0) }
        }
        // On the stack, not on its root content: a pushed `navigationDestination`
        // is not a child of that content and would not inherit this — which is
        // exactly how the Daily Question page shipped crashing while the badge,
        // rendered inside the root, worked fine.
        .environment(identity)
        .sheet(isPresented: $showSettings) {
            CoupleSettingsSheet(identity: identity)
        }
        .onAppear {
            pulse = true
            // Returning from the Apps tab while a sub-page is pushed would
            // otherwise restart the accelerometer behind it — onChange can't
            // catch that, because heroCovered never changed.
            if !heroCovered { tilt.start() }

            // One-shot, like AppShell's -moonshot latch: without it, every
            // return to this tab would push the page again and Home would be
            // unreachable for the rest of the run.
            guard !didHandleLaunchArguments else { return }
            didHandleLaunchArguments = true
            if launchArguments.contains("-openSettings") { showSettings = true }
            if launchArguments.contains("-specialDates") {
                path.append(HubRoute(entryID: "special-dates"))
            }
            #if DEBUG
            DailyQuestionDebugSeed.runIfRequested(in: modelContext.container,
                                                  identity: identity)
            MemoryDebugSeed.runIfRequested(in: modelContext.container,
                                           identity: identity)
            SparkDebugSeed.runIfRequested(in: modelContext.container,
                                          authorID: identity.authorID)
            #endif
            if launchArguments.contains("-dailyQuestion") {
                path.append(HubRoute(entryID: "daily-question"))
            }
            if launchArguments.contains("-memories") {
                path.append(HubRoute(entryID: "memories"))
            }
        }
        .onDisappear { tilt.stop() }
        .onChange(of: heroCovered) { _, covered in
            // Switching tabs fires onAppear/onDisappear, which brackets tilt
            // when Games is frontmost. Neither a sheet nor a push unmounts this
            // view, so this brackets tilt around both of those instead.
            if covered { tilt.stop() } else { tilt.start() }
        }
    }

    private var settingsButton: some View {
        Button {
            Haptics.tap()
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
        }
        .glassCard(cornerRadius: 20)
        .accessibilityLabel(Text("Our details"))
    }

    /// An unknown or not-yet-live route can't be a dead end (principle 7).
    @ViewBuilder private func destination(for route: HubRoute) -> some View {
        if let entry = HubCatalog.entry(route.entryID), case .page(let make) = entry.kind {
            make()
        } else {
            ZStack {
                // A sub-page like any other: no moon (H16).
                DreamyBackground(showsMoon: false)
                Text("Coming soon")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
    CouplesHomeView()
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
