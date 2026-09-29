// The notes endpoint against Netlify's own local blob server rather than a
// stand-in, so that `list`, prefixes and `onlyIfNew` behave as they will in
// production. See #62.
//
//   node test/notes.mjs
//
// No browser: what a page sends is the browser suite's business
// (test/browser/notes.mjs). This is what the server does with it, and what
// `npm run notes` does with that, run as the real command against the same
// local store with a stand-in `gh` on the PATH.
//
// Needs output/, from `npm test` or a build: the listing is checked against
// the PureScript `Notes.export` it copies.

import { spawn } from "child_process"
import fs from "fs"
import os from "os"
import path from "path"
import { getStore } from "@netlify/blobs"
import { BlobsServer } from "@netlify/blobs/server"
import { handle, MAX_NOTES } from "../netlify/functions/notes.mjs"
import * as Notes from "../output/Flashcards.Notes/index.js"

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

  // --- npm run notes ---
  console.log("\nnpm run notes")
  await store.deleteAll()

  // Two devices, interleaved in time, so oldest-first has to cross keys.
  const PHONE = "c".repeat(32)
  const LAPTOP = "d".repeat(32)
  const sept = Date.parse("2026-09-01T00:00:00Z")
  const a = { at: sept - 60_000, context: "/es · querer · recognition", text: "the hint is confusing" }
  const b = { at: sept + 3_600_000, context: "/verbs · porpara.means", text: "two lines\nof it" }
  const c = { at: sept + 7_200_000, context: "/verbs", text: "reads oddly when the sentence is long and wraps" }
  await put(batch([ a, c ]), PHONE)
  await put(batch([ b ]), LAPTOP)

  const bin = fs.mkdtempSync(path.join(os.tmpdir(), "palabras-gh-"))
  const issues = path.join(bin, "issues.json")
  fs.writeFileSync(path.join(bin, "gh"),
    `#!/usr/bin/env node
const issues = JSON.parse(require("fs").readFileSync(${JSON.stringify(issues)}, "utf-8"))
const found = issues[process.argv[4]]
if (!found) { console.error("no such issue"); process.exit(1) }
console.log(JSON.stringify(found))
`, { mode: 0o755 })
  fs.writeFileSync(issues, JSON.stringify({
    5: { body: "Something else entirely.", comments: [ { body: "the hint is" } ] },
    // Reflowed, as pasting into an issue does.
    6: { body: "From a note:\n\nreads oddly when the\nsentence is  long and wraps", comments: [] },
    7: { body: "", comments: [ { body: "Filed from a note: the hint is confusing." } ] },
  }))
  const archived = path.join(bin, "archive", "notes.jsonl")

  const env = {
    ...process.env,
    PATH: `${bin}${path.delimiter}${process.env.PATH}`,
    NETLIFY_SITE_ID: SITE,
    NETLIFY_AUTH_TOKEN: TOKEN,
    NETLIFY_BLOBS_EDGE_URL: edgeURL,
    NOTES_ARCHIVE: archived,
  }
  // Not `spawnSync`: the blob server it talks to runs in this process, and
  // would never answer.
  const run = (argv, withEnv = env) => new Promise(resolve => {
    const child = spawn(process.execPath, [ "tools/notes.mjs", ...argv ], { env: withEnv })
    let out = "", err = ""
    child.stdout.on("data", d => { out += d })
    child.stderr.on("data", d => { err += d })
    child.on("close", status => resolve({ status, out: out.replace(/\n$/, ""), err }))
  })
  const notes = (...argv) => run(argv)
  const remaining = async () => (await keys()).length
  // By what it says as well as how it exits, since a crash exits 1 too.
  const refuses = (label, r, says) =>
    check(label, { status: r.status, says: r.err.includes(says) }, { status: 1, says: true })

  check("prints every note, oldest first, exactly as the app's Copy all does",
    (await notes()).out, Notes["export"]([ a, b, c ]))
  const everyNote = (await notes()).out
  check("and leaves the pairing keys out of it", [ PHONE, LAPTOP ].some(k => everyNote.includes(k)), false)
  check("--since is from the start of that day, in UTC", (await notes("--since", "2026-09-01")).out, Notes["export"]([ b, c ]))
  refuses("--since refuses what is not a date", await notes("--since", "yesterday"), "not a date")

  const listed = JSON.parse((await notes("--json")).out)
  check("--json is the same notes in the same order, each with its key", listed, [
    { key: `${PHONE}/${a.at}.json`, ...a },
    { key: `${LAPTOP}/${b.at}.json`, ...b },
    { key: `${PHONE}/${c.at}.json`, ...c },
  ])
  const [ ka, kb, kc ] = listed.map(n => n.key)

  refuses("is not run without the site and a token",
    await run([], { ...env, NETLIFY_AUTH_TOKEN: "" }), "needs NETLIFY_SITE_ID and NETLIFY_AUTH_TOKEN")
  check("reading deleted nothing", await remaining(), 3)

  // --- deleting, which never loses the only copy ---
  refuses("--done alone is refused", await notes("--done", ka), "exactly one of")
  refuses("as is --done with both proofs", await notes("--done", ka, "--issue", "7", "--dismiss", "x"), "exactly one of")
  refuses("an issue without the text is refused", await notes("--done", ka, "--issue", "5"), "does not contain this note's text")
  refuses("as is one gh cannot read", await notes("--done", ka, "--issue", "8"), "could not read issue #8")
  refuses("an empty reason is refused", await notes("--done", ka, "--dismiss", "  "), "needs a reason")
  refuses("as is a key that is not a note's", await notes("--done", "../x", "--issue", "7"), "not a note's key")
  refuses("or one that is not there", await notes("--done", `${PHONE}/1.json`, "--dismiss", "x"), "no note at")
  refuses("--issue alone does nothing", await notes("--issue", "7"), "go with --done")
  check("and none of it deleted anything", await remaining(), 3)

  const inComment = await notes("--done", ka, "--issue", "7")
  check("once the issue holds the text, a comment will do", inComment.status, 0)
  check("and it is gone", await store.get(ka), null)
  check("reflowed across lines still counts", (await notes("--done", kc, "--issue", "6")).status, 0)
  check("so both are gone", await keys(), [ kb ])

  // A directory where the archive file should be: the append cannot land.
  fs.mkdirSync(archived, { recursive: true })
  refuses("a dismissal that cannot be archived is refused", await notes("--done", kb, "--dismiss", "not a bug"), "so it is not deleted")
  check("and deletes nothing", await keys(), [ kb ])
  fs.rmSync(archived, { recursive: true })

  check("dismissing it with a reason", (await notes("--done", kb, "--dismiss", " the hint was right ")).status, 0)
  const kept = fs.readFileSync(archived, "utf-8").trim().split("\n").map(l => JSON.parse(l))
  check("archives the note, with the reason beside it",
    kept.map(({ dismissed, ...rest }) => rest), [ { key: kb, ...b, why: "the hint was right" } ])
  check("and when", Math.abs(Date.parse(kept[0].dismissed) - Date.now()) < 60_000, true)
  check("before deleting it", await keys(), [])
  const empty = await notes()
  check("an empty store says so, off the listing", [ empty.out, empty.err.trim() ], [ "", "no notes" ])
  fs.rmSync(bin, { recursive: true, force: true })
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
