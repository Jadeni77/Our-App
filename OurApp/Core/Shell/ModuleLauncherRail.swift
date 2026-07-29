import SwiftUI

/// The module launcher as a trailing-edge rail (P8, superseding the bottom
/// drawer): a slim glass tab that swaps open a vertical column of module
/// tiles, keeping the home's vertical space for the couple hero. Tapping a
/// tile mounts that module full-screen via the `openModule` binding.
struct ModuleLauncherRail: View {
    let modules: [ModuleDescriptor]
    @Binding var openModule: ModuleDescriptor?
    var startsOpen = false

    @State private var isOpen = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isOpen {
                VStack(spacing: 12) {
                    Text("Our space")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    ForEach(modules) { module in
                        tile(module)
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 26)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            toggleTab
        }
        .padding(.trailing, 10)
        .onAppear { if startsOpen { isOpen = true } }
    }

    private var toggleTab: some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.springy) { isOpen.toggle() }
        } label: {
            Image(systemName: isOpen ? "chevron.right" : "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                // 44pt+ hit target (HIG minimum — established review ruling).
                .frame(width: 44, height: 64)
        }
        .glassCard(cornerRadius: 18)
        .accessibilityLabel(Text("Our space"))
    }

    private func tile(_ module: ModuleDescriptor) -> some View {
        Button {
            Haptics.tap()
            openModule = module
        } label: {
            VStack(spacing: 6) {
                Text(module.emoji)
                    .font(.system(size: 34))
                Text(module.name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 84)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Host: View {
        @State var open: ModuleDescriptor?
        var body: some View {
            ModuleLauncherRail(
                modules: [FoodDecisionModule.descriptor],
                openModule: $open,
                startsOpen: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(Theme.duskGradient)
        }
    }
    return Host()
}
