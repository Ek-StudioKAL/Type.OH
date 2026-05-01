import SwiftUI

struct StyleChipRow: View {
    @Binding var selected: StylePreset?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StylePresets.all) { preset in
                    ChipButton(preset: preset, isSelected: selected?.id == preset.id) {
                        selected = (selected?.id == preset.id) ? nil : preset
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

private struct ChipButton: View {
    let preset: StylePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(preset.emoji)
                Text(preset.label)
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.13)),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
