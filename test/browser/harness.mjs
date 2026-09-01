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

export const deckFingerprint = () =>
  readConstant("src/Flashcards/Data/Deck/Spanish.purs", /fingerprint = "([a-f0-9]+)"/)

export const formatVersion = () =>
  Number(readConstant("src/Flashcards/Types/Progress.purs", /currentVersion = (\d+)/))

export const storageKey = "flashcards.es.v1"

// Ranks that share an English gloss with an earlier card, and so are barred
// from production. Read from the deck rather than hardcoded, so fixtures stay
// honest when the deck changes.
export const nonCanonicalRanks = () => {
  const csv = fs.readFileSync(path.join(REPO, "data/es-1000.csv"), "utf-8")
  const seen = new Set()
  const barred = new Set()
  for (const line of csv.split("\n").slice(1)) {
    if (!line.trim()) continue
    const cells = line.match(/("([^"]|"")*"|[^,]*)/g).filter((_, i) => i % 2 === 0)
    const rank = Number(cells[0])
    const english = cells[1].replace(/^"|"$/g, "").replace(/""/g, '"').trim()
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

  const server = http.createServer((req, res) => {
    const rel = req.url === "/" ? "/index.html" : req.url.split("?")[0]
    const file = path.join(PUBLIC, rel)
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
  const open = async ({ stub, seed, scheme, viewport } = {}) => {
    const page = await browser.newPage()
    await page.setViewport(viewport ?? { width: 390, height: 844, deviceScaleFactor: 2 })
    if (scheme) await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: scheme }])
    if (stub) await page.evaluateOnNewDocument(stub)
    page.errors = []
    page.on("pageerror", e => page.errors.push(String(e)))
    await page.goto(base, { waitUntil: "networkidle0" })
    await page.evaluate(() => localStorage.clear())
    if (seed) await page.evaluate((k, s) => localStorage.setItem(k, JSON.stringify(s)), storageKey, seed)
    await page.reload({ waitUntil: "networkidle0" })

    page.text = sel => page.$eval(sel, e => e.textContent).catch(() => null)
    page.tap = async sel => { await page.click(sel); await wait(90) }
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
    await body({ base, browser, check, open, downloads })
  } catch (e) {
    failed++
    console.log(`  ✗ suite threw: ${e.message}`)
  } finally {
    await browser.close()
    server.close()
  }
  return failed
}
