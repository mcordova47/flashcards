// Reading the notes the app has sent, and clearing them once acted on. See #62.
//
//   npm run notes                                  every note, oldest first
//   npm run notes -- --since 2026-09-01            from that day on (UTC)
//   npm run notes -- --json                        the same, with each note's key
//   npm run notes -- --done <key> --issue <n>      delete one that issue #n now holds
//   npm run notes -- --done <key> --dismiss "<why>"  archive it with the reason, then delete
//
// Against the same Netlify Blobs store the function writes, from here rather
// than from inside Netlify, which needs the site and a personal access token:
//
//   NETLIFY_SITE_ID      Site configuration → General → Site ID
//   NETLIFY_AUTH_TOKEN   User settings → Applications → Personal access tokens
//
// The plain listing is exactly `Flashcards.Notes.export`'s format, so a note
// reads the same whether it came off the clipboard or the server and pastes
// into an issue the same way. It leaves out each note's key on purpose: the
// key begins with the device's pairing key, which is a door key to that
// person's progress, and this is the output meant for pasting somewhere
// public. `--json` has the keys.
//
// Nothing here deletes on read, and nothing deletes a note whose text does
// not survive somewhere else. `--done` needs one of two proofs that it does:
// an issue whose body or comments contain the note, checked with `gh` rather
// than taken on trust, or a reason for dismissing it, which is appended with
// the note to a local archive before anything is deleted. `--done` alone is
// refused, as is a bulk purge, which is why there is none.
//
// NETLIFY_BLOBS_EDGE_URL points it at a local blob server instead, which is
// how test/notes.mjs runs it.

import { execFileSync } from "child_process"
import fs from "fs"
import os from "os"
import path from "path"
import { getStore } from "@netlify/blobs"

const USAGE = `usage:
  npm run notes [-- --since <yyyy-mm-dd>] [--json]
  npm run notes -- --done <key> --issue <n>
  npm run notes -- --done <key> --dismiss "<why>"`

const fail = message => {
  console.error(message)
  process.exit(1)
}

// --- arguments ---

const args = process.argv.slice(2)
const flags = {}
for (let i = 0; i < args.length; i++) {
  const flag = args[i]
  if (flag === "--json") { flags.json = true; continue }
  if ([ "--since", "--done", "--issue", "--dismiss" ].includes(flag)) {
    if (i + 1 >= args.length) fail(`${flag} needs a value\n\n${USAGE}`)
    flags[flag.slice(2)] = args[++i]
    continue
  }
  fail(`not an option: ${flag}\n\n${USAGE}`)
}

// --- the store ---

const siteID = process.env.NETLIFY_SITE_ID
const token = process.env.NETLIFY_AUTH_TOKEN
if (!siteID || !token) {
  fail("needs NETLIFY_SITE_ID and NETLIFY_AUTH_TOKEN; see the top of tools/notes.mjs for where each is")
}
const edgeURL = process.env.NETLIFY_BLOBS_EDGE_URL
const store = getStore({ name: "notes", siteID, token, ...(edgeURL ? { edgeURL } : {}) })

// `Flashcards.Notes.stamp` and `export`, written again because this runs
// without a build. test/notes.mjs checks the two agree.
const stamp = ms => new Date(ms).toISOString().slice(0, 16).replace("T", " ") + " UTC"
const exported = notes => notes.map(n => `${stamp(n.at)} · ${n.context}\n${n.text}`).join("\n\n")

const everything = async () => {
  const notes = []
  for await (const page of store.list({ paginate: true })) {
    for (const { key } of page.blobs) {
      const n = await store.get(key, { type: "json" })
      // Gone between the list and the read, most likely to a `--done`
      // running elsewhere.
      if (n !== null) notes.push({ key, at: n.at, context: n.context, text: n.text })
    }
  }
  // Oldest first, as `export` is, whichever device each came from.
  return notes.sort((a, b) => a.at - b.at || (a.key < b.key ? -1 : 1))
}

// --- deleting one ---

// Collapsed, because an issue reflows what is pasted into it: a line break in
// the note may be a space in the issue or the other way round. Nothing
// fancier, since a false "not found" only costs a refusal.
const flat = s => s.replace(/\s+/g, " ").trim()

// Looks for the whole entry, stamp and context included, not just the text.
// The text alone is often a word or two — "typo", "confusing" — and would
// match an issue about something else entirely, which is exactly the mistake
// a triage pass makes. The stamp is to the minute, so the entry is this note.
// It is also what the listing prints and the refusal below asks to be pasted,
// so a note pasted either way passes.
const inIssue = (n, note) => {
  let issue
  try {
    issue = JSON.parse(execFileSync("gh", [ "issue", "view", String(n), "--json", "body,comments" ], {
      encoding: "utf-8", stdio: [ "ignore", "pipe", "pipe" ],
    }))
  } catch (e) {
    fail(`could not read issue #${n} with gh, so cannot confirm the note is in it:\n${e.stderr || e.message}`)
  }
  const wanted = flat(exported([ note ]))
  return [ issue.body ?? "", ...(issue.comments ?? []).map(c => c.body ?? "") ].some(b => flat(b).includes(wanted))
}

// Appended, synced to disk, and read back before the caller deletes anything.
// A note whose only other copy is a write that did not land has no other copy.
const archive = (n, why) => {
  const file = process.env.NOTES_ARCHIVE ?? path.join(os.homedir(), ".flashcards", "notes-archive.jsonl")
  const record = { ...n, dismissed: new Date().toISOString(), why }
  const line = JSON.stringify(record)
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true })
    const fd = fs.openSync(file, "a")
    try {
      fs.writeSync(fd, line + "\n")
      fs.fsyncSync(fd)
    } finally {
      fs.closeSync(fd)
    }
    if (!fs.readFileSync(file, "utf-8").split("\n").includes(line)) throw new Error("not there on reading back")
  } catch (e) {
    fail(`could not archive the note to ${file}, so it is not deleted: ${e.message}`)
  }
  return file
}

const done = async key => {
  if (!/^[a-z0-9]{32}\/\d+\.json$/.test(key)) fail(`not a note's key: ${key}\n(keys are in \`npm run notes -- --json\`)`)
  if (flags.since || flags.json) fail(`--done takes only --issue or --dismiss\n\n${USAGE}`)
  const hasIssue = flags.issue !== undefined
  const hasWhy = flags.dismiss !== undefined
  if (hasIssue === hasWhy) {
    fail("--done needs exactly one of --issue <n>, once the note's text is in that issue,\n" +
      "or --dismiss \"<why>\", which archives it with the reason first.\n" +
      "Nothing deletes the only copy of a note.")
  }

  const n = await store.get(key, { type: "json" })
  if (n === null) fail(`no note at ${key}`)
  const note = { key, at: n.at, context: n.context, text: n.text }

  let where
  if (hasIssue) {
    if (!/^[1-9][0-9]*$/.test(flags.issue)) fail(`not an issue number: ${flags.issue}`)
    if (!inIssue(flags.issue, note)) {
      fail(`issue #${flags.issue} does not contain this note, so it is not deleted. Paste it in first:\n\n` +
        exported([ note ]))
    }
    where = `it is in #${flags.issue}`
  } else {
    if (flags.dismiss.trim() === "") fail("--dismiss needs a reason; it is kept next to the note")
    where = `archived in ${archive(note, flags.dismiss.trim())}`
  }

  await store.delete(key)
  console.log(`deleted ${key}; ${where}`)
}

// --- listing ---

const list = async () => {
  let notes = await everything()
  if (flags.since !== undefined) {
    const from = /^\d{4}-\d{2}-\d{2}$/.test(flags.since) ? Date.parse(`${flags.since}T00:00:00Z`) : NaN
    if (Number.isNaN(from)) fail(`not a date: ${flags.since} (yyyy-mm-dd, in UTC)`)
    notes = notes.filter(n => n.at >= from)
  }
  if (flags.json) console.log(JSON.stringify(notes, null, 2))
  else if (notes.length) console.log(exported(notes))
  // On stderr, so that the listing itself is only ever notes.
  else console.error("no notes")
}

if (flags.done !== undefined) await done(flags.done)
else if (flags.issue !== undefined || flags.dismiss !== undefined) fail(`--issue and --dismiss go with --done\n\n${USAGE}`)
else await list()
