import SwiftUI

@MainActor struct StyleChipRow: View {
    @Binding var selected: StylePreset?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StylePresets.all) { preset in
                    ChipButton(preset: preset, isSelected: selected?.id == preset.id) {
                        selected = (selected?.id == preset.id) ? nil : preset
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

/// Icon per style preset — shared by the ReType chips and LazyPad's sidebar
/// so the two surfaces feel like one design system.
func styleIcon(for preset: StylePreset) -> AppIcon {
    switch preset.id {
    case "boomer":     .boomer
    case "genx":       .genX
    case "millennial": .millennial
    case "genz":       .genZ
    case "alpha":      .genAlpha
    default:           .style
    }
}

@MainActor private struct ChipButton: View {
    let preset: StylePreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var tinted: Bool { isSelected || isHovering }

    private var fillOpacity: Double {
        if isSelected { return 0.10 }
        if isHovering { return 0.08 }
        return 0.05
    }

    private var strokeColor: Color {
        isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18)
    }

    private var labelColor: Color {
        tinted ? Color.accentColor : Color.primary
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(appIcon: styleIcon(for: preset), size: 17, bold: tinted)
            Text(preset.label)
                .font(.callout.weight(tinted ? .semibold : .regular))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(labelColor)
        .background(Capsule().fill(Color.secondary.opacity(fillOpacity)))
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 0.5))
    }

    private var underline: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 0.5)
            .frame(maxWidth: isSelected ? 60 : 0)
            .opacity(isSelected ? 1.0 : 0.0)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                capsule
                underline
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
