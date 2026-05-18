import SwiftUI

enum EditorMode: String, CaseIterable {
    case translate = "Translate"
    case style     = "Style"
    case improve   = "Improve"
    case fix       = "Fix"
}

struct ModeTabs: View {
    @Binding var mode: EditorMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorMode.allCases, id: \.self) { m in
                Button(m.rawValue) { mode = m }
                    .buttonStyle(TabStyle(isSelected: mode == m))
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct TabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
    }
}
