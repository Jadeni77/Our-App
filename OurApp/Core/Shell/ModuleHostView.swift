import SwiftUI

/// A module screen that must own its own exits (Moonshot's in-level pause
/// menu, owner ruling: one door out) raises this to hide the shell's
/// floating X while it's on screen.
struct ModuleChromeHiddenKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    /// The shell's close capability, passed down so a module can offer
    /// "exit game" from its own UI. Nil outside a module host.
    @Entry var moduleClose: (() -> Void)?
}

/// Full-screen container the shell mounts a module in. Adds only a floating
/// glass close button — the module inside stays completely untouched
/// (module contract: the shell never reaches past the entry view; it passes
/// a close capability DOWN and honors a chrome-suppression preference UP,
/// and that is the whole conversation).
struct ModuleHostView: View {
    let module: ModuleDescriptor
    @Environment(\.dismiss) private var dismiss
    @State private var chromeHidden = false

    var body: some View {
        module.makeEntryView()
            .environment(\.moduleClose) { dismiss() }
            .onPreferenceChange(ModuleChromeHiddenKey.self) { chromeHidden = $0 }
            .overlay(alignment: .topTrailing) {
                if !chromeHidden {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            // 44×44 = HIG minimum hit target; this is the only way out of a module.
                            .frame(width: 44, height: 44)
                    }
                    .glassCard(cornerRadius: 22)
                    .padding(.trailing, 16)
                    .accessibilityLabel(Text("Close"))
                }
            }
            .onAppear {
                if module.orientation == .landscape { OrientationGate.enter(.landscape) }
            }
            .onDisappear {
                if module.orientation == .landscape { OrientationGate.exitToPortrait() }
            }
    }
}

#Preview {
    ModuleHostView(module: FoodDecisionModule.descriptor)
}
