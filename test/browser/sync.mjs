export const name = "The progress endpoint"

const KEY = "k7m2p9x4w1n8q3r6t5v0y2z7b4d9f1h3"
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
  const page = await open()
  await page.waitForSelector(".prompt")
  await page.waitForFunction(() => navigator.serviceWorker.controller !== null, { timeout: 20000 })
  const cached = await page.evaluate(async key => {
    const url = `/api/progress/${key}`
    await fetch(url)
    return (await caches.match(url)) !== undefined
  }, KEY)
  check("a fetch through the service worker is not cached", cached, false)
  check("no page errors", page.errors, [])
}
