import jsQR from "jsqr"
import { qrDataUrl } from "../../src/Flashcards/Sync.js"
import { deckFingerprint, slugAt, wait } from "./harness.mjs"

export const name = "The progress endpoint"

const KEY = "k7m2p9x4w1n8q3r6t5v0y2z7b4d9f1h3"
const BASE = 1700000000000
const OTHER = "z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4"

export default async ({ check, open, base, blobs }) => {
  const at = (key, lang = "es") => `${base}/api/progress/${key}/${lang}`
  const mine = { version: 5, language: "es", deck: "654958a3f958", cards: [{ slug: "yo", box: 3, seen: 5, missed: 1, lapses: 0, direction: "recognition", due: 1700000000000 }] }

  check("nothing stored yet", (await fetch(at(KEY))).status, 404)

  // The catch-all in netlify.toml rewrites anything unmatched to index.html
  // with a **200**, so a routing mistake does not 404 - it serves HTML to a
  // JSON client. Status alone cannot tell the two apart; the content type can.
  const missing = await fetch(at(KEY))
  check("and says so as JSON, not as the app's HTML",
    missing.headers.get("content-type"), "application/json")

  check("storing it is accepted",
    (await fetch(at(KEY), { method: "PUT", body: JSON.stringify(mine) })).status, 200)
  check("and it comes back byte for byte", await (await fetch(at(KEY))).json(), mine)

  const grown = { ...mine, cards: [...mine.cards, { slug: "no", box: 1, seen: 1, missed: 0, lapses: 0, direction: "recognition", due: 1700000001000 }] }
  await fetch(at(KEY), { method: "PUT", body: JSON.stringify(grown) })
  check("a second write replaces rather than accumulates",
    (await (await fetch(at(KEY))).json()).cards.length, 2)

  check("another key is a different blob", (await fetch(at(OTHER))).status, 404)
  // Progress is per-language, so each language is its own blob under the one
  // pairing key - and each is then byte-identical to the backup file.
  check("and so is the same key's other language", (await fetch(at(KEY, "de"))).status, 404)

  // Never cached anywhere: a stale blob would silently undo a sync.
  check("responses forbid caching",
    (await fetch(at(KEY))).headers.get("cache-control"), "no-store")

  // --- what it refuses ---
  check("a key of the wrong shape", (await fetch(at("nope"))).status, 400)
  check("a language that is not one", (await fetch(at(KEY, "deutsch"))).status, 400)
  check("or a language with a path in it", (await fetch(at(KEY, "..%2Fes"))).status, 400)
  check("a key with a path in it", (await fetch(at("..%2F..%2Fetc%2Fpasswd"))).status, 400)
  check("an uppercase key, so one key is one blob",
    (await fetch(at(KEY.toUpperCase()))).status, 400)
  check("a body that is not JSON",
    (await fetch(at(KEY), { method: "PUT", body: "not json" })).status, 400)
  check("a body over the cap",
    (await fetch(at(KEY), { method: "PUT", body: JSON.stringify({ pad: "x".repeat(500_001) }) })).status, 413)
  // Counted in bytes, not characters: the decks are full of multi-byte words,
  // and `length` would let nearly twice the cap through.
  check("and one that is only oversized once encoded",
    (await fetch(at(KEY), { method: "PUT", body: JSON.stringify({ pad: "é".repeat(260_000) }) })).status, 413)
  check("a method it does not serve",
    (await fetch(at(KEY), { method: "DELETE" })).status, 405)
  check("none of which touched what was stored",
    (await (await fetch(at(KEY))).json()).cards.length, 2)
  check("and only the one blob was ever written", blobs.size, 1)

  // --- the service worker must stay out of it ---
  const first = await open()
  await first.waitForSelector(".prompt")
  await first.waitForFunction(() => navigator.serviceWorker.controller !== null, { timeout: 20000 })
  const cached = await first.evaluate(async key => {
    const url = `/api/progress/${key}/es`
    await fetch(url)
    return (await caches.match(url)) !== undefined
  }, KEY)
  check("a fetch through the service worker is not cached", cached, false)
  await first.close()
  blobs.clear()

  // --- a device on its own ---
  const phone = await open()
  await phone.waitForSelector(".prompt")
  const phoneKey = await phone.evaluate(() => localStorage.getItem("flashcards.sync-key"))
  check("a fresh device generates a key", /^[a-z0-9]{32}$/.test(phoneKey ?? ""), true)

  for (let i = 0; i < 3; i++) { await phone.tap(".card"); await phone.tap(".got-it") }
  // Sync is on load and at the end of a session, so three cards into a
  // twenty-card session nothing has gone up yet beyond the first seed.
  await phone.reload({ waitUntil: "networkidle0" })
  await phone.waitForSelector(".prompt")
  await wait(400)
  const seeded = JSON.parse(blobs.get(`${phoneKey}.es`) ?? "null")
  check("and uploads what it has", seeded?.cards?.length, 3)
  check("as the same bytes the backup file would hold", seeded, await phone.stored())

  // --- pairing a second device with the link ---
  const laptop = await open({ path: `/?pair=${phoneKey}` })
  await laptop.waitForSelector(".prompt")
  await wait(500)
  check("a pairing link is adopted",
    await laptop.evaluate(() => localStorage.getItem("flashcards.sync-key")), phoneKey)
  // The key is the only secret here; leaving it in the address bar puts it in
  // history and in whatever gets shared next.
  check("and taken back out of the address bar", new URL(laptop.url()).search, "")
  check("the other device's history came down", (await laptop.stored())?.cards?.length, 3)
  // Three cards answered, so the next new word is the fourth.
  check("and the session starts past what was already learned",
    await laptop.text(".prompt"), slugAt(4))

  // --- and back the other way ---
  await laptop.tap(".card")
  await laptop.tap(".got-it")
  await laptop.reload({ waitUntil: "networkidle0" })
  await laptop.waitForSelector(".prompt")
  await wait(400)
  check("what the second device learns goes up too",
    JSON.parse(blobs.get(`${phoneKey}.es`)).cards.length, 4)

  await phone.reload({ waitUntil: "networkidle0" })
  await phone.waitForSelector(".prompt")
  await wait(400)
  check("and comes back down to the first", (await phone.stored()).cards.length, 4)
  check("whose session skips it too", await phone.text(".prompt"), slugAt(5))
  check("no page errors on either", [...phone.errors, ...laptop.errors], [])
  await laptop.close()

  // --- a blob this device cannot place ---
  // Not reachable by pairing, since blobs are per language, but the server is
  // a dumb store and this is the last thing standing between a bad one and
  // somebody's history. It must be left alone, not overwritten and not merged.
  {
    const key = await phone.evaluate(() => localStorage.getItem("flashcards.sync-key"))
    const mine = await phone.stored()
    blobs.set(`${key}.es`, JSON.stringify({
      version: 5, language: "de", deck: deckFingerprint("de"),
      cards: [{ slug: "mal", box: 5, seen: 99, missed: 0, lapses: 0, direction: "production", due: BASE }],
    }))
    await phone.reload({ waitUntil: "networkidle0" })
    await phone.waitForSelector(".prompt")
    await wait(400)
    check("progress for another language is refused", await phone.stored(), mine)
    check("and the bad blob is left where it is, not overwritten",
      JSON.parse(blobs.get(`${key}.es`)).language, "de")
    check("silently, because the card screen is not the place for it",
      await phone.text(".notice"), null)
    // Put it back so the checks below start from a sane server.
    blobs.set(`${key}.es`, JSON.stringify(mine))
    await phone.reload({ waitUntil: "networkidle0" })
    await phone.waitForSelector(".prompt")
    await wait(400)
  }

  // --- what the panel says about it ---
  const note = async page => {
    await page.tap(".panel-toggle")
    await wait(150)
    const text = await page.text(".panel-note.sync")
    await page.dismiss()
    return text
  }

  const syncNow = async page => {
    await page.tap(".panel-toggle")
    ;(await page.byText(".panel-item", "Sync now")).click()
    await wait(400)
    await page.dismiss()
  }

  check("a device that has just exchanged says so", await note(phone), "Everything is synced")
  await phone.tap(".card")
  await phone.tap(".got-it")
  // Sync is on load and at session end, so a card graded mid-session is
  // genuinely not up there yet - and the panel is the only place that says so.
  check("and stops saying it the moment there is something to send",
    await note(phone), "Not synced")
  await syncNow(phone)
  check("which the manual button clears", await note(phone), "Everything is synced")

  await phone.setOfflineMode(true)
  await phone.tap(".card")
  await phone.tap(".got-it")
  await syncNow(phone)
  // A failed exchange stays off the card screen by design. This is where it
  // surfaces, and it has to distinguish "not yet" from "cannot".
  check("a failed attempt says why", await note(phone), "Not synced — no connection")
  await phone.setOfflineMode(false)
  await syncNow(phone)
  check("and it recovers when the network does", await note(phone), "Everything is synced")

  // --- the QR code has to actually scan ---
  // A transposed grid, an off-by-one quiet zone or a mirrored path all still
  // look like a QR code, so reading the picture back is the only check worth
  // making. The grid is rebuilt from the SVG this ships, not from the
  // library's own output, so it tests the part written here.
  {
    const link = `https://palabras.mcord.dev/?pair=${KEY}`
    const svg = decodeURIComponent(qrDataUrl(link).replace("data:image/svg+xml,", ""))
    const size = Number(svg.match(/viewBox="0 0 (\d+)/)[1])
    const grid = Array.from({ length: size }, () => new Array(size).fill(false))
    for (const [, x, y, run] of svg.matchAll(/M(\d+) (\d+)h(\d+)v1h-\d+z/g)) {
      for (let i = 0; i < Number(run); i++) grid[Number(y)][Number(x) + i] = true
    }
    const scale = 4
    const side = size * scale
    const pixels = new Uint8ClampedArray(side * side * 4)
    for (let y = 0; y < side; y++) {
      for (let x = 0; x < side; x++) {
        const shade = grid[Math.floor(y / scale)][Math.floor(x / scale)] ? 0 : 255
        const at = (y * side + x) * 4
        pixels[at] = pixels[at + 1] = pixels[at + 2] = shade
        pixels[at + 3] = 255
      }
    }
    check("the QR code reads back as the pairing link", jsQR(pixels, side, side)?.data, link)
    // The whole picture travels in a data URL. Runs rather than one rect per
    // module is what keeps that reasonable - 712 dark modules would be about
    // 21 KB drawn separately, against 5 KB drawn as 364 runs - so the bound is
    // set to catch a regression to the naive form, not to shave bytes.
    check("and is drawn as runs rather than a rect per module", svg.length < 8000, true)
    // Four modules of white on every side, or a scanner cannot find the code.
    check("with the quiet zone the spec asks for",
      grid[0].some(Boolean) || grid[3].some(Boolean) || grid.some(r => r[3]), false)
  }

  // --- handing the link over ---
  await phone.tap(".panel-toggle")
  ;(await phone.byText(".panel-item", "Sync another device")).click()
  await wait(300)
  check("the sheet shows a scannable code", 
    (await phone.$eval(".pair-qr", e => e.src)).startsWith("data:image/svg+xml,"), true)
  const shown = await phone.$eval(".pair-link", e => e.value)
  // Shown rather than only copied: both the clipboard and a share sheet need a
  // user activation that can be lost on the way through the update loop, and a
  // reader with nothing on screen would have no second move.
  check("the pairing sheet shows the whole link", shown, `${base}/?pair=${phoneKey}`)
  check("and says plainly what the link gives away",
    (await phone.text(".pair-warning")).startsWith("Anyone with this link can read and change"), true)
  ;(await phone.byText(".grade", "Copy link")).click()
  await wait(300)
  check("copying reports what happened, either way",
    ["Link copied", "Couldn't copy it — select the link instead"].includes(await phone.text(".notice")), true)
  check("and leaves the link selected to fall back on",
    await phone.$eval(".pair-link", e => e.selectionEnd - e.selectionStart), shown.length)
  check("and does not throw", phone.errors, [])
  await phone.tap(".sheet-close")

  // --- with no network at all ---
  await phone.setOfflineMode(true)
  await phone.reload({ waitUntil: "domcontentloaded" })
  await phone.waitForSelector(".prompt", { timeout: 20000 })
  check("a failed sync is silent", await phone.text(".notice"), null)
  const before = (await phone.stored()).cards.length
  await phone.tap(".card")
  await phone.tap(".got-it")
  check("and studying carries on regardless", (await phone.stored()).cards.length, before + 1)
  await phone.setOfflineMode(false)
  await phone.close()
}
