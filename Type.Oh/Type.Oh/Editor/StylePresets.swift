import Foundation

struct StylePreset: Identifiable, Sendable {
    let id: String
    let label: String
    let emoji: String
    let promptFragment: String
}

enum StylePresets {
    static let all: [StylePreset] = [
        StylePreset(id: "boomer",    label: "Boomer",    emoji: "📋",
            promptFragment: "Rewrite the following text to be 'common sense' and blunt. Remove all corporate jargon, 'soft' language, or expressions of feeling. Use short, declarative sentences. The tone should be that of a man who spent 40 years in a factory and has no patience for 'fluff'. If the original text is long, make the rewrite much shorter and more dismissive."),
        StylePreset(id: "genx",      label: "Gen X",     emoji: "🕶️",
            promptFragment: "Rewrite the following text in a Gen X style: direct, no-nonsense, slightly dry and sardonic. Skip the corporate fluff and excessive positivity. Speak plainly, as if you've seen it all before and just want to get things done."),
        StylePreset(id: "millennial", label: "Millennial", emoji: "🥑",
            promptFragment: "Rewrite the following text in a Millennial communication style: conversational, self-aware, warm, and relatably honest. It can acknowledge feelings and uncertainty. Avoid jargon but allow natural, grounded humor. The tone should feel human and approachable."),
        StylePreset(id: "genz",      label: "Gen Z",     emoji: "💅",
            promptFragment: "Rewrite the following text in Gen Z style: casual, punchy, and unfiltered. Keep it short. Use current internet-native phrasing — understated irony, deadpan humor, low effort energy on the surface but sharp underneath. No corporate speak, no boomerspeak, no cringe."),
        StylePreset(id: "alpha",     label: "Gen Alpha", emoji: "🔥",
            promptFragment: "Rewrite the following text in Gen Alpha style: ultra-short, high energy, emoji-forward, very online. Think TikTok captions, brainrot humor, rapid-fire tone. Keep it punchy and chaotic in a good way. No long sentences."),
    ]
}
