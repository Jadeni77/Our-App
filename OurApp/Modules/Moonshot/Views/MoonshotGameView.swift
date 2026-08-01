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
    @State private var starsRevealed = false
    /// Moondust minted by this run (wreckage + first-clear bonus), for
    /// the win overlay's dust tick (M31).
    @State private var dustEarned = 0

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
            outcomeOverlay
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
        }
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
                        queueDots(session)
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

                    Button {
                        Haptics.tap()
                        buildLevel(currentIndex)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassCard(cornerRadius: 18)
                    .accessibilityLabel(Text("Replay"))

                    // The reference, reachable where the question arises
                    // (owner amendment #3). A SHEET, deliberately: a push
                    // unmounts the SKView and the flight/settle timers are
                    // wall-clock — browsing demos mid-flight would fast-
                    // forward the shot into a timeout fail (review C1).
                    Button {
                        Haptics.tap()
                        showAbilities = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassCard(cornerRadius: 18)
                    .accessibilityLabel(Text("Abilities"))
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

                    // Earned characters are a choice, never a requirement:
                    // once the couple pool unlocks one, any ready fling can
                    // be swapped — once per level, whoever it goes to.
                    if session.phase == .ready, !session.usedCharacterSwap {
                        ForEach(extraCharacters, id: \.self) { character in
                            if session.currentCharacter != character {
                                Button {
                                    Haptics.tap()
                                    scene?.swapSeatedCharacter(to: character)
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(character.chipColor)
                                            .frame(width: 10, height: 10)
                                        Text("Play as \(String(localized: String.LocalizationValue(character.displayNameKey)))")
                                    }
                                    .font(Theme.display(13))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .glassCard(cornerRadius: 18)
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
                case .theme:
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.rose, Theme.peach],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 54, height: 40)
                case .skin:
                    SlingshotGlyph()
                        .stroke(Color(red: 0.85, green: 0.68, blue: 0.28), lineWidth: 4)
                        .frame(width: 34, height: 46)
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
