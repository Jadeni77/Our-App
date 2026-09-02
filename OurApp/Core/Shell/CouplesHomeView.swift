import SwiftData
import SwiftUI

/// The themed couples home (P4, layout per P8) — now a hub (P16): moonlit
/// background, the two of us in the top corners, the day-counter hero in the
/// middle, and a row of topic tiles above the tab bar that push full
/// sub-pages. The module launcher lives on the Games tab (P11).
///
/// DEBUG launch arguments exist solely so headless screenshot verification can
/// reach a state simctl can't tap to: `-openSettings`, `-specialDates`,
/// `-dailyQuestion`, `-seedDailyQuestion`, `-memories`, `-seedMemories`,
/// `-seedAlbums`, `-seedSpark`, `-seedSparkAtRisk`, `-sparkSheet`.
struct CouplesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var identity = CoupleIdentityStore()
    /// Held for the life of Home so the pull cursor survives between ticks.
    @State private var syncEngine: SyncEngine?
    @Environment(\.scenePhase) private var scenePhase

    @State private var tilt = TiltModel()
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var isPaired = SyncSecretStore.isPaired

    /// Derived, not remembered. The stored flag only knows about the keychain;
    /// this also counts "their records are here", which is the thing you can
    /// actually see on screen.
    private var isConnected: Bool {
        isPaired || ProfileStore.isConnected(in: modelContext)
    }
    @State private var pulse = false
    @State private var path = NavigationPath()
    @State private var didHandleLaunchArguments = false
    @State private var editingProfile = false
    @Query(filter: Profile.visible) private var profiles: [Profile]

    private var myName: String {
        profiles.first { $0.authorID == LocalAuthor.id() }?.name ?? ""
    }

    /// The hero is hidden whenever something covers it — a pushed sub-page or
    /// the settings sheet. Pushing does NOT unmount Home, so without this the
    /// accelerometer would keep running behind a sub-page.
    private var heroCovered: Bool { showSettings || !path.isEmpty }

    /// Builds the transport the settings ask for, or none at all.
    ///
    /// Turning sync off drops the engine, which drops its listener — the phone
    /// stops advertising rather than merely ignoring what arrives.
    private func configureSync() {
        // The engine always exists; **pairing gates the network, not the
        // engine**. Pushing appends to our own outbox, which is a local file,
        // so an unpaired phone builds its history and hands the whole of it
        // over the moment it pairs. `LocalPeerService` refuses to advertise
        // until there is a reason to, which is where the privacy line sits.
        //
        // Which transport that is belongs to `SyncStack`, not here. Home
        // choosing its own gave the app two of them at once — a debug run on a
        // shared folder had Home on the folder and co-op on Bonjour, so turns
        // taken in Moonshot went somewhere Home never looked.
        syncEngine = SyncEngine(context: modelContext,
                                transport: SyncStack.transport,
                                authorID: identity.authorID)
    }

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

                        // Both prompts show when both apply. They were once
                        // one-at-a-time to keep the hero uncluttered, which
                        // hid pairing behind naming — and pairing is the step
                        // that makes the app *shared*, so hiding it made the
                        // single most important setup action look absent.
                        // Two footnote lines is a cheaper price than that.
                        if !isConnected {
                            // **Invitation first, pairing code second.** The
                            // code needs two phones in one room at one moment,
                            // which is the situation this app exists for you
                            // not being in. The link works across a continent
                            // and is the only route that carries a push.
                            CoupleInviteButton()
                            Button {
                                Haptics.tap()
                                showPairing = true
                            } label: {
                                Text("Or pair on the same network")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        if myName.isEmpty {
                            Button {
                                Haptics.tap()
                                editingProfile = true
                            } label: {
                                // Singular, and it goes to your profile. It
                                // said "names" and opened Settings, which is
                                // where names used to be edited — a dead end
                                // the moment that screen stopped holding them.
                                Text("Add your name")
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
        .sheet(isPresented: $editingProfile) { MyProfileSheet(identity: identity) }
        .sheet(isPresented: $showSettings, onDismiss: { isPaired = SyncSecretStore.isPaired }) {
            CoupleSettingsSheet(identity: identity)
        }
        .sheet(isPresented: $showPairing, onDismiss: {
            isPaired = SyncSecretStore.isPaired
            configureSync()
        }) {
            SyncPairingSheet()
        }
        // **Your profile exists from launch, not from the first time you open
        // it.** It was created lazily inside the profile sheet, so a phone
        // whose owner never tapped their own face had no record to send —
        // which is exactly why one phone showed a name the other had never
        // heard of. A record nobody has written yet cannot sync, and nothing
        // said so.
        .task { ProfileStore.mine(in: modelContext, seedingFrom: identity) }
        // Ticks on appear and on every foreground — no timers and no background
        // modes, both of which need entitlements this deliberately avoids.
        // Opening the app is the trigger.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            #if DEBUG
            await SyncDebugLaunch.runIfRequested()
            configureSync()   // pairing may have just happened
            #endif
            let arrived = (try? await syncEngine?.tick()) ?? []
            // Photos that just landed were cached as misses while they were
            // absent; without forgetting them the grid keeps its placeholders
            // until the next launch, which looks exactly like sync failing.
            for id in arrived { MemoryThumbnails.shared.forget(id) }
        }
        // The phone that *showed* the code never touched its own settings, so
        // dismissal isn't the signal on that side.
        .onReceive(NotificationCenter.default.publisher(for: .syncDidPair)) { _ in
            isPaired = true
            Task { _ = try? await syncEngine?.tick() }
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
            configureSync()
            if launchArguments.contains("-openSettings") { showSettings = true }
            if launchArguments.contains("-specialDates") {
                path.append(HubRoute(entryID: "special-dates"))
            }
            #if DEBUG
            DailyQuestionDebugSeed.runIfRequested(in: modelContext.container,
                                                  identity: identity)
            MemoryDebugSeed.runIfRequested(in: modelContext.container,
                                           identity: identity)
            AlbumDebugSeed.runIfRequested(in: modelContext.container,
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
