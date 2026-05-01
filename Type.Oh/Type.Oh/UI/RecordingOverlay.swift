import Combine
import SwiftUI

struct RecordingOverlay: View {
    @State private var elapsed = 0
    @State private var pulsing = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.35 : 0.85)
                .opacity(pulsing ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)

            Text(timeString)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.82), in: Capsule())
        .onAppear { pulsing = true }
        .onReceive(clock) { _ in elapsed += 1 }
    }

    private var timeString: String {
        String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

#Preview {
    RecordingOverlay()
        .padding()
}
