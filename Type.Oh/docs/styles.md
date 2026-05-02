# Style Presets

Type.OH ships five generational style presets for the AI Editor's Style tab. Each rewrites selected text to match a distinct communication register.

---

## Boomer 📋

**Target voice:** Baby Boomer professional. Formal, proper, respectful.

**When to use:** Business emails, cover letters, anything that needs to feel polished and traditional.

**Prompt fragment:**
> Rewrite the following text in a Baby Boomer communication style: formal, proper grammar, respectful, no slang, gets straight to the point without being curt. The tone should feel like a professional email from someone who values tradition and clear, direct language.

---

## Gen X 🕶️

**Target voice:** Cynical realist. Direct, dry, no-nonsense.

**When to use:** Internal memos, Slack messages to peers, anything where you want to cut the fluff.

**Prompt fragment:**
> Rewrite the following text in a Gen X style: direct, no-nonsense, slightly dry and sardonic. Skip the corporate fluff and excessive positivity. Speak plainly, as if you've seen it all before and just want to get things done.

---

## Millennial 🥑

**Target voice:** Self-aware and warm. Conversational, relatable, emotionally honest.

**When to use:** Blog posts, social media, team announcements, anything that should feel human.

**Prompt fragment:**
> Rewrite the following text in a Millennial communication style: conversational, self-aware, warm, and relatably honest. It can acknowledge feelings and uncertainty. Avoid jargon but allow natural, grounded humor. The tone should feel human and approachable.

---

## Gen Z 💅

**Target voice:** Chronically online. Punchy, ironic, understated.

**When to use:** Social captions, DMs, anything where sounding casual and sharp matters more than sounding polished.

**Prompt fragment:**
> Rewrite the following text in Gen Z style: casual, punchy, and unfiltered. Keep it short. Use current internet-native phrasing — understated irony, deadpan humor, low effort energy on the surface but sharp underneath. No corporate speak, no boomerspeak, no cringe.

---

## Gen Alpha 🔥

**Target voice:** TikTok brain. Ultra-short, high energy, emoji-forward.

**When to use:** When you want maximum chaos energy. Not for professional contexts.

**Prompt fragment:**
> Rewrite the following text in Gen Alpha style: ultra-short, high energy, emoji-forward, very online. Think TikTok captions, brainrot humor, rapid-fire tone. Keep it punchy and chaotic in a good way. No long sentences.

---

## Adding new presets

Each preset is defined in `Editor/StylePresets.swift` as a `StylePreset(id:label:emoji:promptFragment:)`. The `id` must be unique. The `promptFragment` is prepended to the selected text and sent to the active AI provider.
