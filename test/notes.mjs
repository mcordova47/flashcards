// The notes endpoint against Netlify's own local blob server rather than a
// stand-in, so that `list`, prefixes and `onlyIfNew` behave as they will in
// production. See #62.
//
//   node test/notes.mjs
//
// No browser: what a page sends is the browser suite's business
// (test/browser/notes.mjs). This is what the server does with it.

import fs from "fs"
import os from "os"
import path from "path"
import { getStore } from "@netlify/blobs"
import { BlobsServer } from "@netlify/blobs/server"
import { handle, MAX_NOTES } from "../netlify/functions/notes.mjs"

let failed = 0
const stable = v => JSON.stringify(v)
const check = (label, actual, expected) => {
  const ok = stable(actual) === stable(expected)
  if (!ok) failed++
  console.log(`  ${ok ? "✓" : "✗"} ${label}` +
    (ok ? "" : `\n      expected ${stable(expected)}\n      actual   ${stable(actual)}`))
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "palabras-notes-"))
const TOKEN = "local"
const SITE = "local"
const server = new BlobsServer({ directory: dir, token: TOKEN })
const { port } = await server.start()
const edgeURL = `http://localhost:${port}`
const store = getStore({ name: "notes", edgeURL, siteID: SITE, token: TOKEN })

const KEY = "a".repeat(32)
const OTHER = "b".repeat(32)

const put = (body, key = KEY, method = "PUT") =>
  handle(new Request(`http://localhost/api/notes/${key}`, {
    method,
    body: method === "PUT" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined,
  }), store)

const batch = notes => ({ version: 1, notes })
const note = (at, text = `note ${at}`) => ({ at, context: "/verbs · porpara.means", text })
const keys = async (prefix = "") => (await store.list({ prefix })).blobs.map(b => b.key).sort()

try {
  console.log("\nThe notes endpoint")

  const first = await put(batch([ note(1000), note(2000) ]))
  check("a batch is taken", first.status, 200)
  check("and says how many it stored", (await first.json()).stored, 2)
  check("one blob per note, under the key", await keys(), [ `${KEY}/1000.json`, `${KEY}/2000.json` ])
  check("holding the note and nothing else",
    await store.get(`${KEY}/1000.json`, { type: "json" }), note(1000))

  const again = await put(batch([ note(1000), note(2000), note(3000) ]))
  check("sending them again is fine", again.status, 200)
  check("and stores only the one that is new", (await again.json()).stored, 1)
  check("so each is stored once", (await keys(`${KEY}/`)).length, 3)

  const edited = await put(batch([ note(1000, "a different text, same moment") ]))
  check("a resend is never a rewrite", (await edited.json()).stored, 0)
  check("so what landed first stays", (await store.get(`${KEY}/1000.json`, { type: "json" })).text, "note 1000")

  const extra = await put(batch([ { ...note(4000), device: "extra field" } ]))
  check("fields a note does not have are not stored",
    extra.status === 200 && await store.get(`${KEY}/4000.json`, { type: "json" }), note(4000))

  await put(batch([ note(1000) ]), OTHER)
  check("another key's notes are its own", await keys(`${OTHER}/`), [ `${OTHER}/1000.json` ])

  // --- refused ---
  const before = await keys()
  const refused = async (label, response, status) => check(label, (await response).status, status)
  await refused("a key of the wrong shape", put(batch([ note(1) ]), "short"), 400)
  await refused("a key smuggling a path", put(batch([ note(1) ]), `${KEY}%2F..`), 400)
  await refused("a read: this is write-only", put(null, KEY, "GET"), 405)
  await refused("a body that is not JSON", put("{"), 400)
  await refused("a version this server does not know", put({ version: 2, notes: [ note(1) ] }), 400)
  await refused("notes that are not a list", put({ version: 1, notes: {} }), 400)
  await refused("a time that is not a whole number", put(batch([ note(1.5) ])), 400)
  await refused("a negative time", put(batch([ note(-1) ])), 400)
  await refused("a note with no text", put(batch([ { at: 5, context: "/" } ])), 400)
  await refused("a note over 5 KB", put(batch([ note(5, "x".repeat(5_000)) ])), 413)
  // Multi-byte, so a character count would let it through.
  await refused("measured in bytes", put(batch([ note(5, "ñ".repeat(2_600)) ])), 413)
  await refused("a batch over 500 KB", put(batch(Array.from({ length: 120 }, (_, i) => note(10 + i, "x".repeat(4_500))))), 413)
  await refused("a batch that is one good note and one bad", put(batch([ note(6), { at: 7 } ])), 400)
  check("and none of it stored anything", await keys(), before)

  // --- the cap ---
  const stored = (await keys(`${KEY}/`)).length
  const room = MAX_NOTES - stored
  const full = await put(batch(Array.from({ length: room }, (_, i) => note(100_000 + i))))
  check(`up to ${MAX_NOTES} under one key`, full.status, 200)
  check("fills it", (await keys(`${KEY}/`)).length, MAX_NOTES)

  const over = await put(batch([ note(100_000), note(999_999) ]))
  check("one more is refused", over.status, 413)
  check("all of the batch, not part of it", await store.get(`${KEY}/999999.json`), null)

  const resent = await put(batch([ note(1000), note(100_000) ]))
  check("but a full key still takes what it already has", resent.status, 200)

  await store.delete(`${KEY}/1000.json`)
  const freed = await put(batch([ note(999_999) ]))
  check("and reading one frees its place", freed.status, 200)

  const elsewhere = await put(batch([ note(2) ]), OTHER)
  check("the cap is per key", elsewhere.status, 200)
} catch (e) {
  failed++
  console.log(`  ✗ threw: ${e.stack}`)
} finally {
  await server.stop()
  fs.rmSync(dir, { recursive: true, force: true })
}

if (failed) {
  console.log(`\n${failed} failed`)
  process.exit(1)
}
