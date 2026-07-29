import SwiftUI

/// The frosted-glass drawer at the bottom of the home (decision P4). Tap or
/// drag it to swap open and reveal the module tiles; tapping a tile mounts
/// that module full-screen via the `openModule` binding.
struct ModuleLauncherDrawer: View {
    let modules: [ModuleDescriptor]
    @Binding var openModule: ModuleDescriptor?
    var startsOpen = false

    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 44, height: 5)
            Text("Our space")
                .font(Theme.display(17))
                .foregroundStyle(.white.opacity(0.9))

            if isOpen {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                    ForEach(modules) { module in
                        tile(module)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                withAnimation(Theme.springy) { isOpen = value.translation.height < 0 }
            }
        )
        .onAppear { if startsOpen { isOpen = true } }
    }

    private func toggle() {
        Haptics.tap()
        withAnimation(Theme.springy) { isOpen.toggle() }
    }

    private func tile(_ module: ModuleDescriptor) -> some View {
        Button {
            Haptics.tap()
            openModule = module
        } label: {
            VStack(spacing: 8) {
                Text(module.emoji)
                    .font(.system(size: 40))
                Text(module.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Host: View {
        @State var open: ModuleDescriptor?
        var body: some View {
            ModuleLauncherDrawer(
                modules: [FoodDecisionModule.descriptor],
                openModule: $open,
                startsOpen: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(Theme.duskGradient)
        }
    }
    return Host()
}
