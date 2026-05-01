import SwiftUI

struct DiffTextView: View {
    let original: String
    let result:   String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            pane(label: "Original", text: original, accent: .secondary)
            Divider()
            pane(label: "Result",   text: result,   accent: .green)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15)))
    }

    @ViewBuilder
    private func pane(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
