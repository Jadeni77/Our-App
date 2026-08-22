import CloudKit
import OSLog
import SwiftUI
import UIKit

/// Inviting the other person into the couple's zone.
///
/// One tap, one link, once. It replaces the pairing code, which asked two
/// people to be holding two phones in the same room at the same moment —
/// exactly the situation this app is built for *not* being in.
struct CoupleInviteButton: View {
    /// Wrapped rather than making `CKShare` itself `Identifiable`: a
    /// retroactive conformance on somebody else's class is a promise about a
    /// type this app does not own.
    private struct Invitation: Identifiable {
        let id = UUID()
        let share: CKShare
    }

    @State private var invitation: Invitation?
    @State private var preparing = false
    @State private var failed = false

    var body: some View {
        Button {
            Haptics.tap()
            Task { await prepare() }
        } label: {
            HStack(spacing: 8) {
                if preparing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "link")
                }
                Text("Invite them")
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .glassCard(cornerRadius: 20)
        .disabled(preparing)
        .sheet(item: $invitation) { CoupleShareSheet(share: $0.share) }
        .alert("Couldn't make the invitation", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check you're signed in to iCloud, then try again.")
        }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        // Asked for at the moment you actually invite someone, rather than at
        // first launch: a permission prompt before the app has done anything
        // for you is a prompt you decline.
        await CoupleSubscription.requestPermission()
        do {
            invitation = Invitation(share: try await CoupleZone.makeShare())
        } catch {
            failed = true
        }
    }
}

/// `UICloudSharingController` is the only supported way to send a `CKShare`,
/// and it is UIKit — so it is wrapped rather than reimplemented. Apple's sheet
/// also handles the parts that are easy to get subtly wrong: revoking access,
/// re-sending, and showing who has accepted.
private struct CoupleShareSheet: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CoupleZone.container)
        // Read-write, and never a public link: this is a two-person app, and
        // the zone holds everything the two of you have written.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for controller: UICloudSharingController) -> String? {
            CoupleZone.shareTitle
        }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: any Error) {
            Logger.sharing.error("share failed: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Logger.sharing.info("share saved")
        }
    }
}

private extension Logger {
    static let sharing = Logger(subsystem: "OurApp", category: "sharing")
}
