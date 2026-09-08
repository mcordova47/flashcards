// Shared rig for the browser suites: serve the built site, drive a real
// Chrome against it, and count assertions.
//
// Chrome is not bundled — puppeteer-core drives whatever is already
// installed. Set CHROME=/path/to/chrome if yours is somewhere unusual.

import http from "http"
import fs from "fs"
import os from "os"
import path from "path"
import puppeteer from "puppeteer-core"
import { fileURLToPath } from "url"
import { handle } from "../../netlify/functions/progress.mjs"

export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
const PUBLIC = path.join(REPO, "public")

const TYPES = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
  ".map": "application/json",
}

const CHROME = [
  process.env.CHROME,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
].filter(Boolean)

const chrome = () => {
  const found = CHROME.find(p => fs.existsSync(p))
  if (!found) throw new Error("No Chrome found. Set CHROME=/path/to/chrome")
  return found
}

// Read from source so a deliberate change needs no test edit, while an
// accidental mismatch between app and source still fails.
const readConstant = (file, pattern) =>
  fs.readFileSync(path.join(REPO, file), "utf-8").match(pattern)[1]

const DECK_MODULE = { es: "Spanish", de: "German" }

export const deckFingerprint = (code = "es") =>
  readConstant(`src/Flashcards/Data/Deck/${DECK_MODULE[code]}.purs`, /fingerprint = "([a-f0-9]+)"/)

export const formatVersion = () =>
  Number(readConstant("src/Flashcards/Types/Progress.purs", /currentVersion = (\d+)/))

export const storageKey = "flashcards.es.v1"

// The shipped Spanish deck, read from the CSV the generator reads. Fixtures
// derive what they need from this rather than hardcoding words, so they stay
// honest when the deck changes.
let deckCache = null
export const spanishDeck = () => deckCache ?? (deckCache = readSpanishDeck())

const readSpanishDeck = () => {
  const csv = fs.readFileSync(path.join(REPO, "data/es-1000.csv"), "utf-8")
  const cell = c => c.replace(/^"|"$/g, "").replace(/""/g, '"').trim()
  return csv.split("\n").slice(1).filter(l => l.trim()).map(line => {
    const cells = line.match(/("([^"]|"")*"|[^,]*)/g).filter((_, i) => i % 2 === 0)
    // The slug is the word verbatim; only a renamed card pins anything else,
    // and none do today. See tools/sync-deck.mjs.
    return { rank: Number(cells[0]), english: cell(cells[1]), word: cell(cells[2]) }
  })
}

// The slug progress is keyed by, for the card standing at a given rank.
// Fixtures still name cards by rank because that is how the deck reads, and
// this is the one place that turns a position into an identity.
export const slugAt = rank => spanishDeck().find(c => c.rank === rank).word

// The stored record for the card at a given rank.
export const storedAt = (cards, rank) => cards.find(c => c.slug === slugAt(rank))

// Ranks that share an English gloss with an earlier card, and so are barred
// from production.
export const nonCanonicalRanks = () => {
  const seen = new Set()
  const barred = new Set()
  for (const { rank, english } of spanishDeck()) {
    if (seen.has(english)) barred.add(rank)
    else seen.add(english)
  }
  return barred
}

// A device with the real voice buried among novelty ones, delivered late the
// way engines actually deliver it.
export const VOICES = [
  { name: "Eddy (Spanish (Spain))", lang: "es-ES" },
  { name: "Mónica", lang: "es-ES" },
  { name: "Eddy (Spanish (Mexico))", lang: "es-MX" },
  { name: "Paulina", lang: "es-MX" },
  { name: "Rocko (Spanish (Mexico))", lang: "es-MX" },
]

export const speechStub = (voices = VOICES, { delay = 250 } = {}) => `
  window.__spoken = []
  window.__cancels = 0
  let busy = false
  let voices = []
  const listeners = []
  Object.defineProperty(window, "speechSynthesis", { configurable: true, value: {
    get speaking() { return busy },
    get pending() { return false },
    cancel() { window.__cancels += 1; busy = false },
    getVoices() { return voices },
    addEventListener(type, fn) { if (type === "voiceschanged") listeners.push(fn) },
    speak(u) {
      busy = true
      window.__spoken.push({ text: u.text, lang: u.lang, rate: u.rate, voice: u.voice && u.voice.name })
    },
  }})
  window.SpeechSynthesisUtterance = function (text) { this.text = text }
  setTimeout(() => { voices = ${JSON.stringify(voices)}; listeners.forEach(f => f()) }, ${delay})
`

export const wait = ms => new Promise(r => setTimeout(r, ms))

// Order-insensitive: key order carries no meaning in JSON.
const stable = v =>
  JSON.stringify(v, (_, x) =>
    x && typeof x === "object" && !Array.isArray(x)
      ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1)))
      : x)

export const run = async (name, body) => {
  if (!fs.existsSync(path.join(PUBLIC, "index.js"))) {
    throw new Error("public/ is not built — run `npm run build` first")
  }

  // Netlify Blobs, in memory. The suites drive the real handler rather than a
  // reimplementation of it, so everything the endpoint can get wrong - key
  // shape, size cap, method, 404 - is tested against the code that ships.
  const blobs = new Map()
  const store = {
    get: async key => blobs.get(key) ?? null,
    set: async (key, value) => { blobs.set(key, value) },
  }

  const server = http.createServer(async (req, res) => {
    if (req.url.startsWith("/api/")) {
      const chunks = []
      for await (const chunk of req) chunks.push(chunk)
      const body = Buffer.concat(chunks)
      const reply = await handle(
        new Request(`http://localhost${req.url}`, {
          method: req.method,
          body: body.length ? body : undefined,
        }),
        store,
      )
      res.writeHead(reply.status, Object.fromEntries(reply.headers))
      return res.end(Buffer.from(await reply.arrayBuffer()))
    }
    // Strip the query before anything else: `/?pair=<key>` is the root, and
    // treating it as a path asks the filesystem to read a directory.
    const asked = req.url.split("?")[0]
    const rel = asked === "/" ? "/index.html" : asked
    let file = path.join(PUBLIC, rel)
    // Mirror the SPA rule in netlify.toml: a path with no file behind it and
    // no extension is a route, and gets the app. Without this the language
    // paths cannot be tested at all.
    if (!fs.existsSync(file) && !path.extname(rel)) file = path.join(PUBLIC, "index.html")
    if (!file.startsWith(PUBLIC) || !fs.existsSync(file)) { res.writeHead(404); return res.end() }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] ?? "application/octet-stream" })
    res.end(fs.readFileSync(file))
  })
  await new Promise(r => server.listen(0, r))
  const base = `http://localhost:${server.address().port}`
  const browser = await puppeteer.launch({ executablePath: chrome(), headless: "new", args: ["--no-sandbox"] })
  const downloads = fs.mkdtempSync(path.join(os.tmpdir(), "palabras-"))

  let failed = 0
  const check = (label, actual, expected) => {
    const ok = stable(actual) === stable(expected)
    if (!ok) failed++
    console.log(`  ${ok ? "✓" : "✗"} ${label}` +
      (ok ? "" : `\n      expected ${stable(expected)}\n      actual   ${stable(actual)}`))
  }

  // Every page starts from a clean slate: pages in one browser share an
  // origin's storage, and a previous block's progress will leak otherwise.
  const open = async ({ stub, seed, scheme, viewport, path = "/" } = {}) => {
    const page = await browser.newPage()
    await page.setViewport(viewport ?? { width: 390, height: 844, deviceScaleFactor: 2 })
    if (scheme) await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: scheme }])
    if (stub) await page.evaluateOnNewDocument(stub)
    page.errors = []
    page.on("pageerror", e => page.errors.push(String(e)))
    await page.goto(base + path, { waitUntil: "networkidle0" })
    await page.evaluate(() => localStorage.clear())
    if (seed) await page.evaluate((k, s) => localStorage.setItem(k, JSON.stringify(s)), storageKey, seed)
    // Navigate again rather than reload: a pairing link takes itself back out
    // of the address bar once adopted, so reloading would land on the stripped
    // URL and the second run would see no link at all.
    await page.goto(base + path, { waitUntil: "networkidle0" })

    page.text = sel => page.$eval(sel, e => e.textContent).catch(() => null)
    page.tap = async sel => { await page.click(sel); await wait(90) }
    // Close the panel by tapping the exposed part of the backdrop, rather than
    // its centre. The backdrop fills the viewport but the panel is a bottom
    // sheet sitting on top of it, and the sheet has grown past halfway - so a
    // click at the centre lands on the panel and does nothing, silently. Aim
    // where a reader would: the gap above it.
    page.dismiss = async () => {
      const y = await page.evaluate(() =>
        Math.round((document.querySelector(".panel")?.getBoundingClientRect().top ?? innerHeight) / 2))
      await page.mouse.click(Math.round(page.viewport().width / 2), y)
      await wait(90)
    }
    page.stored = () => page.evaluate(k => JSON.parse(localStorage.getItem(k) ?? "null"), storageKey)
    page.spoken = () => page.evaluate(() => window.__spoken.filter(u => u.text.trim() !== ""))
    page.byText = async (sel, label) => {
      for (const h of await page.$$(sel)) {
        if (await h.evaluate(e => e.textContent) === label) return h
      }
      throw new Error(`no ${sel} labelled "${label}"`)
    }
    return page
  }

  console.log(`\n${name}`)
  try {
    await body({ base, browser, check, open, downloads, blobs })
  } catch (e) {
    failed++
    console.log(`  ✗ suite threw: ${e.message}`)
  } finally {
    await browser.close()
    server.close()
  }
  return failed
}
