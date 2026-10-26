// IPA columns, and the Spanish drafter, shared by tools/sync-deck.mjs,
// tools/check-ipa.mjs and tools/draft-ipa.mjs (#175).
//
// A column named `IPA <tag>` holds one dialect's transcription, `<tag>` being
// a BCP 47 tag. The generator and the gate find them by that name, so a second
// dialect is a column and an entry in INVENTORY, and nothing that reads the
// deck changes.

// What a transcription may be made of, per dialect: the segments, the stress
// mark, and what the word side itself uses to join words. Everything else is
// refused, so a stray `θ` in es-MX (that is es-ES) or a `[` is caught.
export const INVENTORY = {
  "es-MX": {
    vowels: "aeiou",
    glides: "jw",
    consonants: "pbtdkɡfsxʝmnɲlɾrʃ",
    affricates: ["tʃ"],
  },
}

export const IPA_HEADER = /^IPA (\S+)$/

// [{ tag, column }] for every IPA column the header has.
export const ipaColumns = header =>
  header.flatMap(name => {
    const m = IPA_HEADER.exec(name)
    return m ? [{ tag: m[1], column: name }] : []
  })

// The characters a transcription of this dialect may contain.
export const alphabet = tag => {
  const inv = INVENTORY[tag]
  if (!inv) return null
  return new Set([...inv.vowels, ...inv.glides, ...inv.consonants, "ˈ", " ", "/", "(", ")",
                  ...inv.affricates.flatMap(a => [...a])])
}

// The words of a row, as the word side and the transcription both split them:
// a slashed row is alternatives, a phrase is words, and `(se)` is a clitic
// written onto the stem. Returns the parts a transcription has to match one
// for one.
export const wordParts = text =>
  text.split(" / ").flatMap(alt => alt.trim().split(/\s+/).map(w => w.replace(/\(se\)$/, "")))

// A nucleus is one of a e i o u in a transcription; j and w are glides and
// make no syllable of their own. This is what lets the data say hiatus from
// diphthong without a syllable dot: `ˈdia` is two syllables, `ˈbjen` is one.
export const syllables = ipa => [...ipa].filter(c => "aeiou".includes(c)).length

// ---------------------------------------------------------------------------
// The drafter for es-MX. Broad, phonemic: seseo, yeísmo, no aspiration, no
// [β ð ɣ]. Orthography in, transcription out; it knows nothing about words, so
// everything it cannot know is for a person to check (see `doubts`).

const STRONG = new Set([..."aeoáéóAEO"])
const ACCENTED_WEAK = new Set([..."íú"])
const VOWELS = new Set([..."aeiouáéíóúü"])
const UNACCENT = { á: "a", é: "e", í: "i", ó: "o", ú: "u", ü: "u" }

const ONSET_CLUSTERS = new Set(["pɾ", "bɾ", "tɾ", "dɾ", "kɾ", "ɡɾ", "fɾ", "pl", "bl", "kl", "ɡl", "fl"])

// One word to its transcription.
export const draftWord = raw => {
  const w = raw.toLowerCase()
  const at = i => w[i] ?? ""

  // 1. Letters to tokens: { t: "C"|"V"|"G", ph, stressed? }. `G` is a glide,
  //    resolved after the vowel groups are known, so it starts as "V".
  const tokens = []
  const isLetterVowel = i => VOWELS.has(at(i)) || (at(i) === "y" && (w === "y" || (i === w.length - 1 && VOWELS.has(at(i - 1)))))
  let i = 0
  while (i < w.length) {
    const c = w[i], n = at(i + 1), n2 = at(i + 2)
    const front = n === "e" || n === "i" || n === "é" || n === "í"
    if (isLetterVowel(i)) {
      tokens.push({ t: "V", ph: UNACCENT[c] ?? (c === "y" ? "i" : c), accent: "áéíóú".includes(c), letter: c })
      i++
    } else if (c === "h") { tokens.push({ t: "H" }); i++ }
    else if (c === "c" && n === "h") { tokens.push({ t: "C", ph: "tʃ" }); i += 2 }
    else if (c === "c") { tokens.push({ t: "C", ph: front ? "s" : "k" }); i++ }
    else if (c === "q") { tokens.push({ t: "C", ph: "k" }); i += (n === "u" ? 2 : 1) }
    else if (c === "g" && n === "u" && (n2 === "e" || n2 === "i" || n2 === "é" || n2 === "í")) {
      tokens.push({ t: "C", ph: "ɡ" }); i += 2
    }
    else if (c === "g") { tokens.push({ t: "C", ph: front ? "x" : "ɡ" }); i++ }
    else if (c === "l" && n === "l") { tokens.push({ t: "C", ph: "ʝ" }); i += 2 }
    else if (c === "r" && n === "r") { tokens.push({ t: "C", ph: "r" }); i += 2 }
    else if (c === "r") {
      const prev = at(i - 1)
      tokens.push({ t: "C", ph: (i === 0 || "nls".includes(prev)) ? "r" : "ɾ" }); i++
    }
    else if (c === "x") { tokens.push({ t: "C", ph: "k" }, { t: "C", ph: "s" }); i++ }
    else {
      const ph = { b: "b", v: "b", d: "d", f: "f", j: "x", k: "k", l: "l", m: "m", n: "n", ñ: "ɲ", p: "p",
                   s: "s", t: "t", y: "ʝ", z: "s", w: "w" }[c]
      if (ph === undefined) throw new Error(`no rule for ${JSON.stringify(c)} in ${raw}`)
      tokens.push({ t: "C", ph }); i++
    }
  }

  // 2. Vowel groups: a run of V tokens with no H or consonant between. A
  //    group splits into hiatus where both sides are strong, or either side
  //    is an accented i/u.
  const groups = []
  for (let k = 0; k < tokens.length; k++) {
    if (tokens[k].t !== "V") continue
    const prev = groups[groups.length - 1]
    const last = prev && prev[prev.length - 1]
    const joined = last === k - 1
      && !(STRONG.has(tokens[last].letter) && STRONG.has(tokens[k].letter))
      && !ACCENTED_WEAK.has(tokens[last].letter) && !ACCENTED_WEAK.has(tokens[k].letter)
    if (joined) prev.push(k); else groups.push([k])
  }
  // The nucleus of a group is its strong vowel, else its last vowel; the rest
  // are glides, before or after it.
  for (const g of groups) {
    let nuc = g.find(k => STRONG.has(tokens[k].letter))
    if (nuc === undefined) nuc = g[g.length - 1]
    for (const k of g) {
      if (k === nuc) continue
      tokens[k].t = "G"
      tokens[k].ph = tokens[k].ph === "i" ? "j" : "w"
      tokens[k].after = k > nuc
    }
    g.nucleus = nuc
  }

  // 3. Syllables. Each nucleus starts a syllable; the consonants between two
  //    nuclei split before the last one, or before the last two where they are
  //    a stop or f followed by r, or a stop or f followed by l.
  const nuclei = groups.map(g => g.nucleus)
  const cut = [0]           // token index each syllable starts at
  for (let s = 1; s < nuclei.length; s++) {
    const from = nuclei[s - 1] + 1, to = nuclei[s]
    // Offglides stay with the previous syllable; onglides go with the next.
    let a = from
    while (a < to && tokens[a].t === "G" && tokens[a].after) a++
    let b = to
    while (b > a && tokens[b - 1].t === "G" && !tokens[b - 1].after) b--
    const run = []
    for (let k = a; k < b; k++) if (tokens[k].t === "C") run.push(k)
    let boundary
    if (run.length === 0) boundary = b
    else if (run.length === 1) boundary = run[0]
    else {
      const [x, y] = run.slice(-2)
      boundary = ONSET_CLUSTERS.has(tokens[x].ph + tokens[y].ph) ? x : y
    }
    cut.push(boundary)
  }

  // 4. Stress. An accent mark says where; otherwise the last syllable, or the
  //    one before it where the word ends in a vowel, n or s.
  let stressed = -1
  const marked = nuclei.findIndex(k => tokens[k].accent)
  if (nuclei.length > 1) {
    if (marked >= 0) stressed = marked
    else {
      const finalLetter = w[w.length - 1]
      const endsOpen = (VOWELS.has(finalLetter) && finalLetter !== "y") || "ns".includes(finalLetter)
      stressed = endsOpen ? nuclei.length - 2 : nuclei.length - 1
    }
  }

  let out = ""
  for (let k = 0; k < tokens.length; k++) {
    const sy = cut.indexOf(k)
    if (sy === stressed && sy >= 0) out += "ˈ"
    if (tokens[k].ph) out += tokens[k].ph
  }
  return out
}

// A row's word side to its transcription: each word of a phrase and each side
// of a slash transcribed, `(se)` kept as it is.
export const draftRow = foreign => {
  const alts = foreign.split(" / ").map(alt =>
    alt.trim().split(/\s+/).map(word => {
      const clitic = word.endsWith("(se)")
      return draftWord(clitic ? word.slice(0, -4) : word) + (clitic ? "(se)" : "")
    }).join(" "))
  return alts.join(" / ")
}

// Why a person should look at this row: the things the drafter cannot know.
export const doubts = foreign => {
  const why = []
  const w = foreign.toLowerCase()
  // qu and gu before e/i, and ch, are one letter's worth of sound, not a glide
  // or an h.
  const plain = w.replace(/qu(?=[eiéí])/g, "k").replace(/gu(?=[eiéí])/g, "g").replace(/ch/g, "c")
  if (/\s|\//.test(foreign) || foreign.includes("(se)")) why.push("not one plain word")
  if (/[A-ZÁÉÍÓÚ]/.test(foreign)) why.push("capital letter")
  if (w.includes("x")) why.push("x")
  if (/[aeoáéó][aeoáéó]|[aeiou][íú]|[íú][aeiou]/.test(w)) why.push("hiatus")
  if (/[iu][aeiouáéó]|[aeoáéó][iu]|ui|iu/.test(plain)) why.push("diphthong")
  if (/y$/.test(w) && w.length > 1) why.push("final y")
  if (/[kw]/.test(w)) why.push("k or w: loan")
  if (/h/.test(plain.slice(1)) && !/[aeiouáéíóú]h[aeiouáéíóú]/.test(plain)) why.push("h inside a word")
  if (/^(aun|solo|sólo)$/.test(w)) why.push("accent-sensitive")
  return why
}
