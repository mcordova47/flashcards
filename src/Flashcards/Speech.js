export const supported = () =>
  typeof window !== "undefined" && "speechSynthesis" in window

export const speak_ = text => {
  const synth = window.speechSynthesis
  if (!synth) return

  // Tapping twice should repeat the word, not queue a backlog behind it.
  synth.cancel()

  const utterance = new SpeechSynthesisUtterance(text)
  utterance.lang = "es-ES"
  // A shade under natural pace: these are single words being learned, not prose.
  utterance.rate = 0.9

  // getVoices() is empty until the engine warms up, but by the time anyone has
  // flipped a card it is populated. If no Spanish voice is installed, the lang
  // hint alone still gets Spanish pronunciation out of most engines.
  const voices = synth.getVoices()
  const spanish =
    voices.find(v => v.lang === "es-ES") ||
    voices.find(v => v.lang.replace("_", "-").startsWith("es"))
  if (spanish) utterance.voice = spanish

  synth.speak(utterance)
}
