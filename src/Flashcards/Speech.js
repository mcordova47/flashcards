export const supported = () =>
  typeof window !== "undefined" && "speechSynthesis" in window

const spanishVoices = () => {
  const synth = typeof window === "undefined" ? null : window.speechSynthesis
  if (!synth) return []
  return synth
    .getVoices()
    .map(v => ({ voice: v, name: v.name, lang: v.lang.replace("_", "-"), isDefault: v.default }))
    .filter(v => v.lang.toLowerCase().startsWith("es"))
}

const accents = () => [...new Set(spanishVoices().map(v => v.lang))].sort()

export const onAccents_ = handler => {
  const emit = () => {
    const found = accents()
    if (found.length) handler(found)
  }
  // Engines populate getVoices() asynchronously; during startup it is reliably
  // empty, so emitting once is not enough.
  emit()
  if (window.speechSynthesis && window.speechSynthesis.addEventListener) {
    window.speechSynthesis.addEventListener("voiceschanged", emit)
  }
}

// Prefer the engine's own default, then a plain name: on Apple platforms every
// novelty voice carries a "(Spanish (Region))" suffix that the real voices —
// Mónica, Paulina — do not, so this picks the useful one out of the nine each
// locale offers.
const bestVoiceFor = locale => {
  const candidates = spanishVoices().filter(v => v.lang === locale)
  const pick =
    candidates.find(v => v.isDefault) ||
    candidates.find(v => !v.name.includes("(")) ||
    candidates[0]
  return pick ? pick.voice : null
}

export const speak_ = (locale, text) => {
  const synth = window.speechSynthesis
  if (!synth) return

  // Tapping twice should repeat the word, not queue a backlog behind it.
  synth.cancel()

  const utterance = new SpeechSynthesisUtterance(text)
  utterance.lang = locale
  // A shade under natural pace: these are single words being learned, not prose.
  utterance.rate = 0.9

  // If the locale has no voice installed, the lang hint alone still gets
  // Spanish pronunciation out of most engines.
  const voice = bestVoiceFor(locale)
  if (voice) utterance.voice = voice

  synth.speak(utterance)
}
