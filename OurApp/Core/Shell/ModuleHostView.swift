import SwiftUI

/// Full-screen container the shell mounts a module in. Adds only a floating
/// glass close button — the module inside stays completely untouched
/// (module contract: the shell never reaches past the entry view).
struct ModuleHostView: View {
    let module: ModuleDescriptor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        module.makeEntryView()
            .overlay(alignment: .topTrailing) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .glassCard(cornerRadius: 22)
                .padding(.trailing, 16)
                .accessibilityLabel(Text("Close"))
            }
    }
}

#Preview {
    ModuleHostView(module: FoodDecisionModule.descriptor)
}
