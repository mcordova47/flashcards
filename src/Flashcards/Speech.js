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
const rank = list =>
  list.find(v => v.isDefault) || list.find(v => !v.name.includes("(")) || list[0] || null

// Exact locale first, then any Spanish voice at all. Handing the engine no
// voice lets it fall back to its own default, which on a US machine is an
// English voice reading Spanish text — the worst possible outcome and worse
// than the wrong flavour of Spanish.
const bestVoiceFor = locale => {
  const spanish = spanishVoices()
  const found = rank(spanish.filter(v => v.lang === locale)) || rank(spanish)
  return found ? found.voice : null
}

export const speak_ = (locale, text) => {
  const synth = window.speechSynthesis
  if (!synth) return

  const utterance = new SpeechSynthesisUtterance(text)
  // A shade under natural pace: these are single words being learned, not prose.
  utterance.rate = 0.9

  const voice = bestVoiceFor(locale)
  if (voice) {
    utterance.voice = voice
    // Match lang to the voice actually chosen. Engines that re-resolve from
    // lang will otherwise discard the voice when the two disagree — which is
    // how you end up with an English voice reading Spanish.
    utterance.lang = voice.lang
  } else {
    utterance.lang = locale
  }

  // Chrome is known to mis-voice or silently drop an utterance queued in the
  // same tick as a cancel(). Only cancel when there is something to cancel,
  // and let the queue settle before speaking.
  if (synth.speaking || synth.pending) {
    synth.cancel()
    setTimeout(() => synth.speak(utterance), 80)
  } else {
    synth.speak(utterance)
  }
}
