import SwiftUI
import SwiftData
import SpriteKit

/// Hosts the SpriteKit scene with the HUD on top. The view is the
/// coordinator: it builds scene + session together (retry and next-level are
/// rebuilds), watches the observable session for win/fail, and writes the
/// result record exactly once per outcome.
struct MoonshotGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The shell's close capability (M32): "Exit game" leaves the module
    /// entirely; "Home" only pops this level.
    @Environment(\.moduleClose) private var moduleClose
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    @State private var scene: GameScene?
    @State private var session: LevelSession?
    @State private var recordedOutcome = false
    @State private var newGrants: [RewardGrant] = []
    /// This run's pool movement, for the win overlay's economy line (M26).
    @State private var poolDelta = 0
    @State private var poolNow = 0
    /// Bumped per rebuild: SpriteView keeps presenting its ORIGINAL scene
    /// when the scene parameter changes, so Replay/Next level showed the old
    /// rubble driving a dead session (found on the owners' device pass —
    /// headless verification could never press Replay). New identity forces
    /// a fresh SKView that presents the new scene.
    @State private var sceneGeneration = 0
    /// Pinned at level build — the pool can't change mid-level, and the HUD
    /// re-evaluates far too often to refetch every result row each time.
    @State private var extraCharacters: [CharacterID] = []
    /// Feats bookkeeping (M23): destroyed-piece count feeds CLEAN SWEEP;
    /// the earned set lights the win overlay's badges.
    @State private var destroyedPieces = 0
    @State private var earnedFeats: Set<Feat> = []
    /// Coach moments (M25) owed at this level open; goal/drag/cue handled
    /// here, cards and banners in their own views.
    @State private var coachMoments: [CoachMoment] = []
    @State private var showGoalLine = false
    @State private var showAbilityCue = false
    @State private var pendingIntroCards: [CharacterID] = []
    /// World-mechanic and gloom-kind banners, shown one at a time after
    /// the cards clear.
    @State private var pendingBanners: [CoachMoment] = []
    @State private var showAbilities = false
    /// The pause menu (M32, owner ruling: one door out). Opening it
    /// freezes the scene's simulation and wall-clock bookkeeping.
    @State private var showPauseMenu = false
    /// A just-unlocked character's ability card, shown over the win card
    /// until explicitly confirmed (owner request).
    @State private var unlockCardCharacter: CharacterID?
    @State private var starsRevealed = false
    /// Moondust minted by this run (wreckage + first-clear bonus), for
    /// the win overlay's dust tick (M31).
    @State private var dustEarned = 0
    /// The fling picker (M31): choose who flies next. Wallet balance and
    /// star pool are snapshotted on open (and balance after each spend) —
    /// neither can change while a modal moment is up, and per-render
    /// store fetches are exactly what the HUD forbids.
    @State private var showFlingPicker = false
    @State private var pickerBalance = 0
    @State private var pickerPool = 0

    private let catalog = CampaignCatalog.bundled
    #if DEBUG
    @MainActor private static var autoFlingFired = false
    #endif

    init(levelIndex: Int) {
        _currentIndex = State(initialValue: levelIndex)
    }

    var body: some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene)
                    .id(sceneGeneration)
                    .ignoresSafeArea()
            } else {
                DreamyBackground()
            }
            hud
            coachOverlay
            flingPickerOverlay
            outcomeOverlay
            pauseMenuOverlay
            if let character = pendingIntroCards.first {
                CoachCardView(character: character, unlocked: true) {
                    MoonshotProgressStore(context: modelContext)
                        .markCoachSeen(.meetCharacter(character))
                    // Guarded: a double-fire on the last card must not trap
                    // on an empty array (review finding).
                    withAnimation {
                        if !pendingIntroCards.isEmpty { pendingIntroCards.removeFirst() }
                    }
                }
                .id(character)
                .transition(.opacity)
            }
            // The unlock moment teaches ON THE SPOT (owner request: "show
            // the ability inside the gameplay until the user manually
            // confirms"): a character grant blocks the win card with its
            // ability card — read it, confirm it, then celebrate. Marked
            // seen so the level-open intro card won't repeat it.
            if let character = unlockCardCharacter {
                CoachCardView(character: character, unlocked: true) {
                    MoonshotProgressStore(context: modelContext)
                        .markCoachSeen(.meetCharacter(character))
                    withAnimation { unlockCardCharacter = nil }
                }
                .id(character)
                .transition(.opacity)
            }
        }
        // MID-level, the pause menu is the one door out (owner ruling): no
        // shell X, no system back. Finished levels are the exception —
        // the outcome card offers its own Back to home.
        // Conditional on a scene existing: a failed build (DEBUG
        // out-of-range level) has no gear, and hiding the chrome there
        // would leave no door at all (review finding).
        .preference(key: ModuleChromeHiddenKey.self, value: scene != nil)
        .navigationBarBackButtonHidden(scene != nil)
        .onAppear {
            if scene == nil { buildLevel(currentIndex) }
            MoonshotAudio.shared.startAmbience()
        }
        .onDisappear {
            MoonshotAudio.shared.stopAmbience()
        }
        .onChange(of: session?.phase) { _, phase in
            coachOnPhaseChange(phase)
            guard case .won(let stars) = phase, !recordedOutcome, let session else { return }
            recordedOutcome = true
            let store = MoonshotProgressStore(context: modelContext)
            let poolBefore = store.starPool
            let grantsBefore = MoonshotRewards.grants(pool: poolBefore)
            // Checked BEFORE recording — recordSolo flips `cleared` and
            // would make every win look like a rerun.
            let firstClear = store.result(for: session.level.id)?.cleared != true
            earnedFeats = FeatDetector.feats(
                flingsUsed: session.flingsUsed,
                usedAnyAbility: session.usedAnyAbility,
                destructiblePieces: session.level.pieces.filter { $0.material != .frame }.count,
                destroyedPieces: destroyedPieces)
            store.recordSolo(levelID: session.level.id,
                             cleared: true,
                             stars: stars,
                             flings: session.flingsUsed,
                             feats: earnedFeats)
            // Destruction pays (M31): wreckage mints dust every run,
            // the first clear adds its bonus once.
            let wreckDust = (scene?.wreckageValue ?? 0) * MoonshotTuning.moondustPerCost
            if wreckDust > 0 { store.addMoondust(wreckDust, reason: "wreckage") }
            if firstClear { store.addMoondust(MoonshotTuning.moondustFirstClear, reason: "first-clear") }
            dustEarned = wreckDust + (firstClear ? MoonshotTuning.moondustFirstClear : 0)
            poolNow = store.starPool
            poolDelta = poolNow - poolBefore
            let grantsAfter = MoonshotRewards.grants(pool: poolNow)
            newGrants = grantsAfter.filter { !grantsBefore.contains($0) }
            // A newly earned STAR gets its lesson right now, not next
            // level: the ability card blocks until confirmed.
            if case .character(let unlocked)? = newGrants.first(where: {
                if case .character = $0 { true } else { false }
            }) {
                unlockCardCharacter = unlocked
            }
            Haptics.success()
            #if DEBUG
            // `-moonshotAutoReplay`: after a win, drive the exact rebuild
            // path the Replay button uses, then fling again — the headless
            // stand-in for pressing Replay (which simctl can't tap).
            if ProcessInfo.processInfo.arguments.contains("-moonshotAutoReplay") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    buildLevel(currentIndex)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        scene?.demoFling(pull: CGVector(dx: -53, dy: -53))
                    }
                }
            }
            #endif
        }
    }

    private func buildLevel(_ index: Int) {
        guard catalog.levels.indices.contains(index) else { return }
        currentIndex = index
        recordedOutcome = false
        newGrants = []
        destroyedPieces = 0
        earnedFeats = []
        starsRevealed = false
        dustEarned = 0
        showFlingPicker = false
        showPauseMenu = false
        unlockCardCharacter = nil
        freeSwitchSpent = false
        sceneGeneration += 1
        let store = MoonshotProgressStore(context: modelContext)
        let pool = store.starPool
        extraCharacters = [CharacterID.nox, .misty].filter {
            MoonshotRewards.isUnlocked($0, pool: pool)
        }
        var level = catalog.levels[index]
        #if DEBUG
        // `-moonshotQueue zip,twinkle,nox` swaps the loaded level's lineup —
        // keeps level data honest while letting screenshots exercise any cast.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-moonshotQueue"),
           arguments.indices.contains(flag + 1) {
            let queue = arguments[flag + 1].split(separator: ",")
                .compactMap { CharacterID(rawValue: String($0)) }
            if !queue.isEmpty { level.queue = queue }
        }
        // `-moonshotGloomKind shield` recasts EVERY gloom in the loaded
        // level — variant behaviors verify headlessly on any stage.
        if let flag = arguments.firstIndex(of: "-moonshotGloomKind"),
           arguments.indices.contains(flag + 1),
           let kind = GloomKind(rawValue: arguments[flag + 1]) {
            level.glooms = level.glooms.map { .init(x: $0.x, y: $0.y, kind: kind) }
        }
        #endif
        let newSession = LevelSession(level: level)
        let newScene = GameScene(level: level,
                                 session: newSession,
                                 showsTrajectoryHint: index < MoonshotTuning.trajectoryHintLevels,
                                 trail: store.equippedTrail,
                                 slingshotSkin: store.equippedSkin)
        // Haptics live here, not in the Engine — the scene stays a physics
        // world; the view decides what the hand feels.
        newScene.onEvent = { event in
            switch event {
            case .flung, .gloomPopped: Haptics.tap()
            case .pieceDestroyed:
                destroyedPieces += 1   // CLEAN SWEEP's ledger (M23)
                Haptics.thud()
            case .impact, .levelWon, .levelFailed: break   // won/failed haptics ride onChange
            }
        }
        session = newSession
        scene = newScene
        startCoaching(for: level, scene: newScene, store: store)
        #if DEBUG
        // `-moonshotSwap zip` swaps the ready fling at open (session-level,
        // free first pick) and `-moonshotFlingPicker` opens the picker —
        // together they screenshot the priced state headlessly.
        if let flag = arguments.firstIndex(of: "-moonshotSwap"),
           arguments.indices.contains(flag + 1),
           let character = CharacterID(rawValue: arguments[flag + 1]) {
            newSession.swapCurrentCharacter(to: character)
        }
        if arguments.contains("-moonshotFlingPicker") {
            pickerBalance = store.moondustBalance()
            pickerPool = store.starPool   // matches the real door's snapshot
            showFlingPicker = true
        }
        // `-moonshotPauseMenu [delay]` opens the menu once the scene is
        // mounted (default 1.5 s) — simctl can't tap the gear. A delay
        // past the autofling launch pauses MID-FLIGHT, which is how the
        // freeze itself gets verified with something moving.
        if let flag = arguments.firstIndex(of: "-moonshotPauseMenu") {
            let delay = arguments.indices.contains(flag + 1)
                ? Double(arguments[flag + 1]) ?? 1.5 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak newScene] in
                newScene?.pauseGameplay()
                showPauseMenu = true
            }
        }
        // One-shot per app run: the auto-fling exists to drive the FIRST
        // build of a verification run. Without the latch it re-fired on
        // every Replay/Next level — ambushing anyone hand-testing the
        // simulator after a debug launch with ghost flings.
        if arguments.contains("-moonshotAutoFling"), !Self.autoFlingFired {
            Self.autoFlingFired = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak newScene] in
                newScene?.demoFling(pull: CGVector(dx: -53, dy: -53))
            }
            // `-moonshotAbilityDelay 0.5` taps the ability that long after release.
            if let flag = arguments.firstIndex(of: "-moonshotAbilityDelay"),
               arguments.indices.contains(flag + 1),
               let delay = Double(arguments[flag + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + 0.6 + delay) { [weak newScene] in
                    newScene?.demoTapAbility()
                }
            }
        }
        #endif
    }

    // MARK: Coach moments (M25)

    private func startCoaching(for level: MoonshotLevel, scene: GameScene, store: MoonshotProgressStore) {
        coachMoments = CoachLedger.momentsAtLevelOpen(level: level,
                                                      swapCharacters: extraCharacters,
                                                      seen: store.seenCoachKeys())
        showGoalLine = false
        showAbilityCue = false
        pendingIntroCards = coachMoments.compactMap {
            if case .meetCharacter(let character) = $0 { character } else { nil }
        }
        pendingBanners = coachMoments.filter {
            switch $0 {
            case .worldMechanic, .meetGloom: true
            default: false
            }
        }
        // Goal/banner mark seen and start their fade timers in .onAppear —
        // intro cards cover this layer, and a caption that fades behind a
        // card was never taught (found in PR-2 verification).
        if coachMoments.contains(.goal) {
            showGoalLine = true
        }
        if coachMoments.contains(.dragToFling) {
            scene.showDragHint(reduceMotion: reduceMotion)
            scene.onDragHintDismissed = { [modelContext] in
                MoonshotProgressStore(context: modelContext).markCoachSeen(.dragToFling)
            }
        }
    }

    private func bannerText(_ moment: CoachMoment) -> Text {
        switch moment {
        case .worldMechanic(2):
            Text("Cloudfoam bounces you — aim off the pads")
        case .worldMechanic(4):
            Text("The deep glooms fight back — watch their tricks")
        case .worldMechanic:
            Text("Wind bends every arc — trust your read, not the dots")
        case .meetGloom(.shield):
            Text("Its shell breaks first — hit it twice")
        case .meetGloom(.hopper):
            Text("It jumps when you land close — bait it")
        case .meetGloom(.mist):
            Text("Only a power can touch the mist")
        case .meetGloom(.great):
            Text("The Great Gloom shrugs — chip away")
        default:
            Text("")
        }
    }

    private func coachOnPhaseChange(_ phase: LevelSession.Phase?) {
        guard case .inFlight = phase else {
            showAbilityCue = false
            return
        }
        showGoalLine = false
        pendingBanners = []
        let store = MoonshotProgressStore(context: modelContext)
        guard CoachLedger.momentInFlight(seen: store.seenCoachKeys()) == .abilityTap else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [modelContext] in
            guard case .inFlight = session?.phase, session?.abilityUsedThisFlight == false else { return }
            // Seen means "the cue fired", not "the tap was obeyed" — it
            // must never nag a player who chose to save the ability.
            MoonshotProgressStore(context: modelContext).markCoachSeen(.abilityTap)
            withAnimation { showAbilityCue = true }
        }
    }

    @ViewBuilder
    private var coachOverlay: some View {
        VStack(spacing: 10) {
            if pendingIntroCards.isEmpty, let banner = pendingBanners.first {
                bannerText(banner)
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 16)
                    .transition(.opacity)
                    .id(banner.storageKey)   // fresh onAppear per banner
                    .onAppear {
                        MoonshotProgressStore(context: modelContext).markCoachSeen(banner)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation {
                                if pendingBanners.first == banner {
                                    pendingBanners.removeFirst()
                                }
                            }
                        }
                    }
            }
            if pendingIntroCards.isEmpty, showGoalLine {
                Text("Pop every gloom to relight the sky")
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 16)
                    .transition(.opacity)
                    .onAppear {
                        MoonshotProgressStore(context: modelContext).markCoachSeen(.goal)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { showGoalLine = false }
                        }
                    }
            }
            if showAbilityCue, let session,
               session.phase == .inFlight, !session.abilityUsedThisFlight,
               let character = session.currentCharacter {
                Text("Tap — \(String(localized: String.LocalizationValue(character.displayNameKey)))'s power!")
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 16)
                    .modifier(NudgePulse(active: !reduceMotion))
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.top, 58)
        .allowsHitTesting(false)
    }

    // MARK: HUD

    private var hud: some View {
        VStack {
            HStack(spacing: 10) {
                if let session {
                    HStack(spacing: 10) {
                        Text("W\(session.level.worldNumber) · L\(currentIndex + 1)")
                            .foregroundStyle(.white.opacity(0.7))
                        // The door to the picker (M31) must LOOK like a
                        // door (owner: bare dots read as decoration, and
                        // moondust "seems just like numbers" when its one
                        // spend is invisible): current star's name + a
                        // swap glyph + the queue dots, one visible chip.
                        Button {
                            Haptics.tap()
                            let store = MoonshotProgressStore(context: modelContext)
                            pickerBalance = store.moondustBalance()
                            pickerPool = store.starPool
                            showFlingPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                if let current = session.currentCharacter {
                                    Text(LocalizedStringKey(current.displayNameKey))
                                        .font(Theme.display(13))
                                        .foregroundStyle(.white)
                                }
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.glow)
                                queueDots(session)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .contentShape(Capsule())
                        }
                        .disabled(session.phase != .ready)
                        .accessibilityLabel(Text("Choose your star"))
                        // "Current fling" = the airborne one mid-flight, the
                        // next one when ready (review note from the engine PR).
                        let current = switch session.phase {
                        case .ready, .aiming: session.flingsUsed + 1
                        default: max(session.flingsUsed, 1)
                        }
                        Text("Fling \(min(current, max(session.level.queue.count, 1)))")
                        Text("Par \(session.level.par)")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(Theme.display(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 18)

                    // Replay, abilities, home, and exit all live behind ONE
                    // system button now (owner amendment 2026-08-01): the
                    // gear pauses the world and opens the menu.
                    Button {
                        Haptics.tap()
                        scene?.pauseGameplay()
                        showPauseMenu = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassCard(cornerRadius: 18)
                    .accessibilityLabel(Text("Menu"))
                    // A SHEET, deliberately (review C1): a push unmounts
                    // the SKView. The game stays paused beneath it and the
                    // menu waits behind for the "‹".
                    .sheet(isPresented: $showAbilities) {
                        NavigationStack {
                            AbilityDashboardView(initial: session.currentCharacter ?? .mochi)
                                // Sheets get no system back — supply the
                                // same "‹" at the same top-left spot.
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            Haptics.tap()
                                            showAbilities = false
                                        } label: {
                                            Image(systemName: "chevron.backward")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                        .accessibilityLabel(Text("Back"))
                                    }
                                }
                        }
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// One dot per sprite still in the queue, wearing its character's color
    /// (the current one is full-size and bright; the rest wait in line).
    private func queueDots(_ session: LevelSession) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(session.upcomingCharacters.enumerated()), id: \.offset) { index, character in
                Circle()
                    .fill(character.chipColor.opacity(index == 0 ? 1 : 0.5))
                    .frame(width: index == 0 ? 10 : 8, height: index == 0 ? 10 : 8)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Pause menu (M32)

    /// The mid-level door out (owner ruling): while a level is live, every
    /// way to leave or restart lives here, behind the gear — the world
    /// stays frozen underneath. Outcome cards add their own Back to home
    /// once the level is decided.
    @ViewBuilder
    private var pauseMenuOverlay: some View {
        if showPauseMenu {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { resumeFromMenu() }
                VStack(spacing: 12) {
                    Text("Paused")
                        .font(Theme.display(20))
                        .foregroundStyle(.white)
                    Button { resumeFromMenu() } label: {
                        Text("Resume").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MoonshotOverlayButton(prominent: true))
                    Button {
                        Haptics.tap()
                        showPauseMenu = false
                        buildLevel(currentIndex)   // a fresh scene needs no resume
                    } label: {
                        Text("Replay level").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MoonshotOverlayButton(prominent: false))
                    Button {
                        Haptics.tap()
                        showAbilities = true       // menu waits behind the sheet
                    } label: {
                        Text("Abilities").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MoonshotOverlayButton(prominent: false))
                    Button {
                        Haptics.tap()
                        dismiss()                   // pop to the constellation/hub
                    } label: {
                        Text("Back to home").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MoonshotOverlayButton(prominent: false))
                    Button {
                        Haptics.tap()
                        moduleClose?()              // leave Moonshot entirely
                    } label: {
                        Text("Exit game").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MoonshotOverlayButton(prominent: false))
                }
                .frame(maxWidth: 300)
                .padding(24)
                .glassCard(cornerRadius: 26)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { resumeFromMenu() }
            }
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    private func resumeFromMenu() {
        Haptics.tap()
        scene?.resumeGameplay()
        showPauseMenu = false
    }

    // MARK: Fling picker (M31)

    /// Choose who flies next: every character, locked ones dimmed with
    /// their threshold. The first pick each level is free; repeats cost
    /// moondust. The spend fires only when the session actually swapped —
    /// a veto (phase changed under the overlay) never charges.
    @ViewBuilder
    private var flingPickerOverlay: some View {
        if showFlingPicker, let session {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showFlingPicker = false }
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            Haptics.tap()
                            showFlingPicker = false
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel(Text("Back"))
                        Spacer()
                        HStack(spacing: 5) {
                            MoondustGem()
                                .fill(Theme.glow)
                                .frame(width: 11, height: 11)
                            Text("\(pickerBalance)")
                                .font(Theme.display(14))
                                .foregroundStyle(Theme.glow)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Moondust"))
                        .accessibilityValue(Text("\(pickerBalance)"))
                    }
                    Text("Choose your star")
                        .font(Theme.display(17))
                        .foregroundStyle(.white)
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(CharacterID.allCases, id: \.self) { character in
                            pickerChoice(character, session: session)
                        }
                    }
                }
                .padding(22)
                .glassCard(cornerRadius: 24)
                .frame(maxWidth: 460)
                // A modal to touches must be a modal to VoiceOver too, or
                // focus walks through the scrim onto Replay and rebuilds
                // the level under the open picker (review finding; same
                // treatment as CoachCardView).
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { showFlingPicker = false }
            }
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    /// True once this level's FREE switch is spent. Tracked apart from
    /// the session's swapsUsed: a paid Nox summon must not burn the free
    /// tier — the player would be double-charged 40 + 25 while the card
    /// still promises a free first switch (review finding).
    @State private var freeSwitchSpent = false

    /// What picking this character costs right now. Nil = free. Nox is
    /// summoned, never owned (M34): every pick costs, even the level's
    /// first switch — the well is too strong to hand out with the track.
    private func pickPrice(_ character: CharacterID) -> Int? {
        if character == .nox { return MoonshotTuning.noxSummonPrice }
        return freeSwitchSpent ? MoonshotTuning.moondustSwapPrice : nil
    }

    private func pickerChoice(_ character: CharacterID, session: LevelSession) -> some View {
        let unlocked = MoonshotRewards.isUnlocked(character, pool: pickerPool)
        let current = session.currentCharacter == character
        let price = pickPrice(character)
        let affordable = price.map { pickerBalance >= $0 } ?? true
        return Button {
            Haptics.tap()
            let store = MoonshotProgressStore(context: modelContext)
            // Affordability re-checked against the store, not the snapshot:
            // a swap must never be granted on a spend that would fail
            // (review finding — future dust sinks could stale the snapshot).
            if let price {
                guard store.moondustBalance() >= price else {
                    pickerBalance = store.moondustBalance()
                    return
                }
            }
            let before = session.swapsUsed
            scene?.swapSeatedCharacter(to: character)
            if session.swapsUsed > before {
                if let price {
                    store.spendMoondust(price, reason: character == .nox ? "nox-summon" : "swap")
                    pickerBalance = store.moondustBalance()
                } else {
                    freeSwitchSpent = true
                }
            }
            showFlingPicker = false
        } label: {
            let threshold = MoonshotRewards.track.first {
                $0.grant == .character(character)
            }?.threshold
            VStack(spacing: 6) {
                Circle()
                    .fill(character.chipColor.opacity(unlocked ? 1 : 0.35))
                    .frame(width: 34, height: 34)
                    .overlay {
                        if current {
                            Circle().strokeBorder(.white, lineWidth: 2)
                        }
                    }
                Text(LocalizedStringKey(character.displayNameKey))
                    .font(Theme.display(12))
                    .foregroundStyle(.white.opacity(unlocked ? 0.9 : 0.5))
                if !unlocked, let threshold {
                    Text("\(threshold)★")
                        .font(.caption2)
                        .foregroundStyle(Theme.glow.opacity(0.8))
                } else if current {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                } else if let price {
                    HStack(spacing: 3) {
                        MoondustGem()
                            .fill(Theme.glow)
                            .frame(width: 8, height: 8)
                        Text("\(price)")
                            .font(.caption2)
                            .foregroundStyle(Theme.glow.opacity(affordable ? 1 : 0.5))
                    }
                } else {
                    Text("Free")
                        .font(.caption2)
                        .foregroundStyle(Theme.glow)
                }
            }
        }
        .disabled(!unlocked || current || !affordable)
        .accessibilityValue(pickerChoiceValue(
            unlocked: unlocked, current: current, price: price, character: character))
    }

    /// What VoiceOver says after the character's name — the price line.
    private func pickerChoiceValue(unlocked: Bool, current: Bool, price: Int?,
                                   character: CharacterID) -> Text {
        if !unlocked, let threshold = MoonshotRewards.track.first(where: {
            $0.grant == .character(character)
        })?.threshold {
            Text("Unlocks at \(threshold)★")
        } else if current {
            Text("")
        } else if let price {
            Text("\(price)")
        } else {
            Text("Free")
        }
    }

    // MARK: Win / fail overlays

    @ViewBuilder
    private var outcomeOverlay: some View {
        switch session?.phase {
        case .won(let stars):
            outcomeCard {
                starRow(stars)
                starReason
                featBadges
                if newGrants.isEmpty {
                    // The economy line: what this run banked, what's next.
                    HStack(spacing: 8) {
                        if poolDelta > 0 {
                            Text("+\(poolDelta)★")
                                .font(Theme.display(15))
                                .foregroundStyle(Theme.glow)
                        }
                        NextUnlockStrip(pool: poolNow)
                    }
                    .frame(maxWidth: 320)
                } else {
                    VStack(spacing: 8) {
                        Text("New unlock!")
                            .font(Theme.display(15))
                            .foregroundStyle(Theme.glow)
                        HStack(spacing: 18) {
                            ForEach(Array(newGrants.enumerated()), id: \.offset) { _, grant in
                                grantMedallion(grant)
                            }
                        }
                    }
                }
                if dustEarned > 0 {
                    // Destruction's payout (M31), under the star economy.
                    HStack(spacing: 5) {
                        MoondustGem()
                            .fill(Theme.glow)
                            .frame(width: 11, height: 11)
                        Text("+\(dustEarned) moondust")
                            .font(Theme.display(14))
                            .foregroundStyle(Theme.glow.opacity(0.9))
                    }
                }
                HStack(spacing: 14) {
                    Button { buildLevel(currentIndex) } label: { Text("Replay") }
                        .buttonStyle(MoonshotOverlayButton(prominent: false))
                    if currentIndex + 1 < catalog.levels.count {
                        Button { buildLevel(currentIndex + 1) } label: { Text("Next level") }
                            .buttonStyle(MoonshotOverlayButton(prominent: true))
                    }
                }
                // The quiet way out (owner request): a finished level can
                // hand you straight back instead of forcing another run.
                Button {
                    dismiss()
                } label: {
                    Text("Back to home")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        case .failed:
            outcomeCard {
                Text("😵‍💫").font(.system(size: 40))
                    .accessibilityLabel(Text("Level failed"))
                Text("The glooms giggle. Try again?")
                    .font(Theme.display(15))
                    .foregroundStyle(.white.opacity(0.85))
                Button { buildLevel(currentIndex) } label: { Text("Try again") }
                    .buttonStyle(MoonshotOverlayButton(prominent: true))
                Button {
                    dismiss()
                } label: {
                    Text("Back to home")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        default:
            EmptyView()
        }
    }

    private func outcomeCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 18) {
            content()
        }
        .padding(28)
        .glassCard(cornerRadius: 28)
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }

    /// The reason under the stars (owner amendment #2): the economy must
    /// say WHY, not just how many.
    @ViewBuilder
    private var starReason: some View {
        if let session {
            Group {
                if session.flingsUsed <= session.level.par {
                    Text("At or under par — 3 stars")
                } else if session.flingsUsed == session.level.par + 1 {
                    Text("One over par — 2 stars")
                } else {
                    Text("Cleared — 1 star")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// A grant rendered as a thing, not a line of text (M26): swatch or
    /// portrait, glowing in, with its name underneath.
    private func grantMedallion(_ grant: RewardGrant) -> some View {
        VStack(spacing: 6) {
            ZStack {
                switch grant {
                case .trail(let trail):
                    Capsule()
                        .fill(LinearGradient(colors: [trailColor(trail), .white.opacity(0.35)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 58, height: 26)
                case .character(let character):
                    Circle()
                        .fill(character.chipColor)
                        .frame(width: 54, height: 54)
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                case .theme(let theme):
                    let veil: LinearGradient = switch theme {
                    case .dawn: LinearGradient(colors: [Theme.rose, Theme.peach],
                                               startPoint: .top, endPoint: .bottom)
                    case .midnight: LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.22), Theme.indigo],
                                                   startPoint: .top, endPoint: .bottom)
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .fill(veil)
                        .frame(width: 54, height: 40)
                case .skin(let skin):
                    // Obsidian gets the same glow edge the in-scene node
                    // needed (review finding: near-black stroke on the
                    // dark W4 win card read as a faint halo, not a fork).
                    switch skin {
                    case .golden:
                        SlingshotGlyph()
                            .stroke(Color(red: 0.85, green: 0.68, blue: 0.28), lineWidth: 4)
                            .frame(width: 34, height: 46)
                    case .obsidian:
                        ZStack {
                            SlingshotGlyph()
                                .stroke(Theme.glow, lineWidth: 6)
                            SlingshotGlyph()
                                .stroke(Color(red: 0.12, green: 0.10, blue: 0.18), lineWidth: 4)
                        }
                        .frame(width: 34, height: 46)
                    }
                }
            }
            .frame(height: 56)
            .shadow(color: Theme.glow.opacity(0.8), radius: 12)
            grant.titleText
                .font(Theme.display(14))
                .foregroundStyle(.white)
        }
        .transition(.scale(scale: 0.4).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private func trailColor(_ trail: TrailID) -> Color {
        switch trail {
        case .stardust: Theme.glow
        case .petals: Theme.rose
        case .aurora: Color(red: 0.45, green: 0.85, blue: 0.75)
        case .nebula: Color(red: 0.62, green: 0.5, blue: 0.95)
        case .comet: Color(red: 1, green: 0.9, blue: 0.6)
        }
    }

    /// The three feat badges (M23) — earned ones glow, the rest wait dim.
    /// Pure bragging, never currency.
    private var featBadges: some View {
        HStack(spacing: 16) {
            featBadge("hare.fill", Text("One fling"), earned: earnedFeats.contains(.oneFling))
            featBadge("hand.raised.fill", Text("No ability"), earned: earnedFeats.contains(.noAbility))
            featBadge("sparkles", Text("Clean sweep"), earned: earnedFeats.contains(.cleanSweep))
        }
    }

    private func featBadge(_ icon: String, _ label: Text, earned: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16))
            label
                .font(Theme.display(11))
        }
        .foregroundStyle(earned ? Theme.glow : Color.white.opacity(0.3))
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!earned)
    }

    /// Stars pop in one after another, a haptic tick each (M28); Reduce
    /// Motion shows them settled.
    private func starRow(_ stars: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 30))
                    .foregroundStyle(i < stars ? Color.yellow : .white.opacity(0.4))
                    .scaleEffect(starsRevealed || reduceMotion ? 1 : 0.2)
                    .opacity(starsRevealed || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil
                               : .spring(duration: 0.3).delay(Double(i) * 0.15),
                               value: starsRevealed)
            }
        }
        .onAppear {
            starsRevealed = true
            guard !reduceMotion else { return }
            for i in 0..<stars {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.15) {
                    Haptics.tap()
                }
            }
        }
        .accessibilityLabel(Text("\(stars) stars"))
    }
}

extension CharacterID {
    /// SwiftUI color for HUD chips, derived from the one Engine palette
    /// (Views-layer on purpose: Rules stays UI-free). Nox's chip lightens
    /// his near-black body color — a true-color dot vanishes on glass.
    var chipColor: Color {
        switch self {
        case .nox: Color(red: 0.45, green: 0.42, blue: 0.72)
        default: Color(bodyUIColor)
        }
    }
}

/// A tiny Y-fork slingshot outline for the golden-skin medallion.
private struct SlingshotGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY))
        return path
    }
}

/// A gentle breathing scale for the ability cue; static under Reduce Motion.
private struct NudgePulse: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulsing ? 1.08 : 1)
            .animation(active ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default,
                       value: pulsing)
            .onAppear { pulsing = true }
    }
}

private struct MoonshotOverlayButton: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(prominent ? Theme.indigo : Color.white.opacity(0.2))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    MoonshotGameView(levelIndex: 0)
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
