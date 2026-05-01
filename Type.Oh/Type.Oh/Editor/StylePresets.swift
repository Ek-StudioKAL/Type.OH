import Foundation

struct StylePreset: Identifiable, Sendable {
    let id: String
    let label: String
    let emoji: String
    let promptFragment: String
}

enum StylePresets {
    static let all: [StylePreset] = [
        StylePreset(id: "formal",    label: "Formal",    emoji: "🤝",
            promptFragment: "Rewrite the following text in a formal, professional tone."),
        StylePreset(id: "concise",   label: "Concise",   emoji: "✂️",
            promptFragment: "Rewrite the following text to be shorter and more concise, removing all unnecessary words."),
        StylePreset(id: "friendly",  label: "Friendly",  emoji: "😊",
            promptFragment: "Rewrite the following text in a warm, friendly, and approachable tone."),
        StylePreset(id: "corporate", label: "Corporate", emoji: "💼",
            promptFragment: "Rewrite the following text in a polished corporate business communication style."),
        StylePreset(id: "pirate",    label: "Pirate",    emoji: "🏴‍☠️",
            promptFragment: "Rewrite the following text as if it were written by a swashbuckling pirate. Be creative and fun with pirate slang and expressions, matey!"),
    ]
}
