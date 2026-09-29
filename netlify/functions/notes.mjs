// Where a note written in the app goes, so that it reaches someone who can act
// on it. See #62.
//
//   PUT /api/notes/<key>   stores each note in the body that is not already stored
//
// Delivery, not sync: nothing here is ever read back by a device, so there is
// no GET, no merge and nothing a client has to reconcile. The notes are read
// by `npm run notes`, against the same store.
//
// The body is exactly `Flashcards.Notes.toJson` of the notes being sent. Each
// is stored as a blob of its own at `<key>/<at>.json`: `at` is millis and is
// unique under one device's key, so the blob key is deterministic, and sending
// a note twice stores it once. That is what lets the client be careless about
// retries.
//
// Its own function rather than a namespace under /api/progress: that route is
// read-and-replace, one blob per namespace, and this is append-only and
// write-only. Sharing the handler would mean each one refusing the other's
// verbs.

import { getStore } from "@netlify/blobs"

export const config = { path: "/api/notes/:key" }

// The same key as progress, for the same reasons. See progress.mjs.
const KEY = /^[a-z0-9]{32}$/

// Append-only is unbounded unless something bounds it, so a key's notes are
// capped at about what one progress blob may hold: a hundred notes of up to
// 5 KB each. Nobody writes a hundred notes before the first has been read, and
// reading one is what frees its place (`npm run notes -- --done`).
//
// Per key, like progress, which is all a server with no accounts can do: keys
// are minted by the client, so someone set on free storage mints another. What
// the cap stops is one key growing without end.
export const MAX_NOTES = 100
const MAX_NOTE_BYTES = 5_000
const MAX_BYTES = 500_000

// Only the version `Flashcards.Notes` writes. A newer app will say so, and
// guessing at what it meant would store something nobody can read correctly.
const VERSION = 1

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  })

const bytes = s => new TextEncoder().encode(s).length

// Exactly the fields a note has, re-serialised from what was checked, so that
// nothing else a client sends along is stored.
const readNote = n =>
  n !== null && typeof n === "object" &&
  Number.isSafeInteger(n.at) && n.at >= 0 &&
  typeof n.context === "string" && typeof n.text === "string"
    ? JSON.stringify({ at: n.at, context: n.context, text: n.text })
    : null

// Split from the default export so tests can drive it against a local store,
// as progress.mjs is.
export const handle = async (request, store) => {
  // From the end, for the same reason as progress: the request may arrive
  // through the redirect in netlify.toml rather than `config.path`.
  const key = new URL(request.url).pathname.split("/").map(decodeURIComponent).at(-1)
  if (!KEY.test(key ?? "")) return json(400, { error: "not a valid key" })

  if (request.method !== "PUT") return json(405, { error: "PUT only" })

  const body = await request.text()
  if (bytes(body) > MAX_BYTES) return json(413, { error: "too large" })

  let parsed
  try {
    parsed = JSON.parse(body)
  } catch {
    return json(400, { error: "not valid JSON" })
  }
  if (parsed?.version !== VERSION || !Array.isArray(parsed.notes)) {
    return json(400, { error: "not a list of notes this server knows" })
  }

  const incoming = new Map()
  for (const n of parsed.notes) {
    const blob = readNote(n)
    if (blob === null) return json(400, { error: "not a note" })
    if (bytes(blob) > MAX_NOTE_BYTES) return json(413, { error: "a note is too large" })
    incoming.set(`${key}/${n.at}.json`, blob)
  }

  // What is already stored is skipped rather than written again, and does not
  // count twice towards the cap: a resend is the normal case, not an abuse.
  const { blobs } = await store.list({ prefix: `${key}/` })
  const stored = new Set(blobs.map(b => b.key))
  const fresh = [...incoming].filter(([at]) => !stored.has(at))

  // All or nothing, so that a device over the cap keeps every note it has
  // rather than having some of them silently land. It will try again on the
  // next sync, by which time some may have been read and freed their place.
  //
  // Best effort under concurrency: two batches racing can each see room that
  // only one of them has. The overshoot is one batch, and one device's notes.
  if (stored.size + fresh.length > MAX_NOTES) {
    return json(413, { error: "too many notes stored under this key" })
  }

  // `onlyIfNew`, so a note that landed between the list and here is left as
  // it is rather than written over with the same bytes.
  for (const [at, blob] of fresh) await store.set(at, blob, { onlyIfNew: true })
  return json(200, { ok: true, stored: fresh.length })
}

export default request => handle(request, getStore("notes"))
