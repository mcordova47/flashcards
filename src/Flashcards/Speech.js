export const supported = () =>
  typeof window !== "undefined" && "speechSynthesis" in window

const spanishVoices = () => {
  const synth = typeof window === "undefined" ? null : window.speechSynthesis
  if (!synth) return []
  return synth
    .getVoices()
    .map(v => ({ voice: v, name: v.name, locale: v.lang.replace("_", "-") }))
    .filter(v => v.locale.toLowerCase().startsWith("es"))
}

export const onVoices_ = handler => {
  const emit = () => {
    const found = spanishVoices()
    if (found.length) handler(found.map(v => ({ name: v.name, locale: v.locale })))
  }
  // Engines populate getVoices() asynchronously; during startup it is reliably
  // empty, so emitting once is not enough.
  emit()
  if (window.speechSynthesis && window.speechSynthesis.addEventListener) {
    window.speechSynthesis.addEventListener("voiceschanged", emit)
  }
}

const findVoice = (name, locale) => {
  const spanish = spanishVoices()
  const exact = spanish.find(v => v.name === name && v.locale === locale)
  const inLocale = spanish.filter(v => v.locale === locale)[0]
  const any = spanish[0]
  const found = exact || inLocale || any
  return found ? found.voice : null
}

export const speak_ = (name, locale, text) => {
  const synth = window.speechSynthesis
  if (!synth) return

  let already = false
  const go = () => {
    if (already) return
    already = true
    utter(synth, name, locale, text)
  }

  // A cold engine reports no voices at all, and speaking then falls through to
  // whatever default is loaded — an English one on a US machine.
  if (spanishVoices().length) {
    go()
  } else {
    if (synth.addEventListener) synth.addEventListener("voiceschanged", go, { once: true })
    setTimeout(go, 600)
  }
}

const utter = (synth, name, locale, text) => {
  const utterance = new SpeechSynthesisUtterance(text)
  // A shade under natural pace: these are single words being learned, not prose.
  utterance.rate = 0.9

  const voice = findVoice(name, locale)
  if (voice) {
    utterance.voice = voice
    // Match lang to the voice actually chosen, or engines that re-resolve from
    // lang will discard it.
    utterance.lang = voice.lang
  } else {
    utterance.lang = locale
  }

  // Chrome is known to mis-voice or drop an utterance queued in the same tick
  // as a cancel(), so only cancel when something is in flight.
  if (synth.speaking || synth.pending) {
    synth.cancel()
    setTimeout(() => synth.speak(utterance), 80)
  } else {
    synth.speak(utterance)
  }
}
