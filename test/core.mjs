// The contract of `core.js`: what another client imports, and that it does what
// the app does. See core.js and #169.
//
//   node test/core.mjs
//
// Run against the built `public/core.v1.js`, the file that ships, so it needs
// `npm run build` first; `verify` runs it after the build.

import * as core from "../public/core.v1.js"
import fs from "fs"

let failed = 0
const check = (label, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failed++
  console.log(`  ${ok ? "✓" : "✗"} ${label}`)
  if (!ok) console.log(`      expected ${JSON.stringify(expected)}\n      got      ${JSON.stringify(actual)}`)
}
const throws = (label, f) => {
  let message = null
  try { f() } catch (e) { message = e.message }
  check(label, message !== null, true)
}

const NOW = Date.UTC(2026, 9, 10, 12)
const DAY = 86400000
const cards = progress => JSON.parse(progress).cards
const entry = (progress, slug) => cards(progress).find(c => c.slug === slug)

console.log("\nThe core other clients import")

check("it exports exactly this surface", Object.keys(core).sort(),
  ["card", "empty", "grade", "ipa", "merge", "overview", "requeue", "session", "sessionSize", "version"])
check("at this version", core.version, 1)

const fresh = core.session(null, NOW)
check("a client with no progress is given a full session of distinct slugs",
  [fresh.length, new Set(fresh).size, typeof fresh[0]], [core.sessionSize, core.sessionSize, "string"])
check("and the same one for the empty string and for an empty history",
  [core.session("", NOW), core.session(core.empty(), NOW)], [fresh, fresh])

const first = core.card(null, fresh[0])
check("a card has what a client shows", Object.keys(first).sort(),
  ["answers", "direction", "example", "prompt", "slug"])
check("a new card is asked as recognition, the word first", [first.direction, first.answers.length], ["recognition", 1])

const after = core.grade(null, fresh[0], true, NOW)
check("an answer is recorded under its slug", entry(after, fresh[0]).seen, 1)
check("a right one and a wrong one leave different boxes",
  entry(core.grade(null, fresh[0], false, NOW), fresh[0]).box === entry(after, fresh[0]).box, false)
check("the card answered is no longer due, so it is not in the next session",
  core.session(after, NOW).includes(fresh[0]), false)
check("and is due again later", core.session(after, NOW + 400 * DAY).includes(fresh[0]), true)
check("grading the same card twice counts both", entry(core.grade(after, fresh[0], true, NOW + DAY), fresh[0]).seen, 2)

// The other device, from nothing: an answer given on each, merged either way.
const a = core.grade(null, fresh[0], true, NOW)
const b = core.grade(null, fresh[1], true, NOW)
const slugs = p => cards(p).map(c => c.slug).sort()
check("merging keeps what each side answered", slugs(core.merge(a, b)), [fresh[0], fresh[1]].sort())
check("in either order", slugs(core.merge(b, a)), slugs(core.merge(a, b)))
check("and the side further along on a card wins it",
  entry(core.merge(core.grade(a, fresh[0], true, NOW + DAY), a), fresh[0]).seen, 2)
check("merging with nothing stored is the history itself", slugs(core.merge(a, null)), [fresh[0]])

check("a card's slug has its transcription, in the one dialect there is",
  [core.ipa("yo"), core.ipa("querer", "es-MX"), core.ipa("querer", "es-MX", "es")], ["ʝo", "keˈɾeɾ", "keˈɾeɾ"])
check("and every card in a session has one", fresh.every(s => typeof core.ipa(s) === "string"), true)
check("null for a slug, a dialect and a language that have none",
  [core.ipa("petunia"), core.ipa("yo", "es-ES"), core.ipa("Haus", "es-MX", "de"), core.ipa("Haus", "de-DE", "de")],
  [null, null, null, null])

const idle = core.overview(null, NOW)
check("an overview has what a client shows", Object.keys(idle).sort(),
  ["dueNow", "dueTomorrow", "mastered", "nextDueIn", "seen", "total"])
check("nothing stored is zeroes and no next time, over the whole deck",
  [idle.seen, idle.mastered, idle.dueNow, idle.dueTomorrow, idle.nextDueIn, idle.total > 0], [0, 0, 0, 0, null, true])
check("the empty string and an empty history say the same", [core.overview("", NOW), core.overview(core.empty(), NOW)], [idle, idle])
const met = core.overview(after, NOW + 3600000)
check("a card answered an hour ago is seen, not due, and due again in what is left of its box",
  [met.seen, met.dueNow, met.nextDueIn > 0, Number.isInteger(met.nextDueIn)], [1, 0, true, true])
check("and once it is due it is counted, with nothing ahead", (o => [o.dueNow, o.nextDueIn])(core.overview(after, NOW + 400 * DAY)), [1, null])
const due = entry(after, fresh[0]).due
check("a card due within a day is counted as due tomorrow, and not before",
  [core.overview(after, due - 0.5 * DAY).dueTomorrow, core.overview(after, due - 2 * DAY).dueTomorrow], [1, 0])
const orphaned = JSON.stringify({ ...JSON.parse(after), cards: [...cards(after), { ...entry(after, fresh[0]), slug: "no-longer-in-the-deck", due: NOW }] })
check("history for a slug no longer in the deck is not counted",
  [core.overview(orphaned, NOW + 400 * DAY).seen, core.overview(orphaned, NOW + 400 * DAY).dueNow], [1, 1])
throws("an unknown language throws", () => core.overview(null, NOW, "xx"))

check("a miss comes back a few places on", core.requeue("x", 0, ["a", "b", "c", "d", "e", "f"]).indexOf("x") > 1, true)

// A module import across origins is refused without this, and nothing else in
// the repository would notice: the file is served, and only a browser on
// another origin fails.
const toml = fs.readFileSync("netlify.toml", "utf8")
check("the core files are served with CORS, since a module import needs it",
  /for = "\/core\*\.js"\s+\[headers\.values\]\s+Access-Control-Allow-Origin = "\*"/.test(toml), true)
check("and the versioned file is the bare one",
  fs.readFileSync("public/core.js", "utf8") === fs.readFileSync("public/core.v1.js", "utf8"), true)

throws("a language there is not is refused", () => core.session(null, NOW, "xx"))
throws("so is a language for a transcription", () => core.ipa("yo", "es-MX", "xx"))
throws("so is a card there is not", () => core.grade(null, "no-such-card", true, NOW))
throws("so is progress that is not progress", () => core.session("{not json", NOW))
throws("and progress for the other language", () => core.session(core.empty("de"), NOW, "es"))

console.log(failed ? `\n  ${failed} failed\n` : "\n  all passed\n")
process.exit(failed ? 1 : 0)
