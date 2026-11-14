// Runs the browser suites against the built site.
//
//   npm run verify              every suite
//   npm run verify -- speech    just the ones matching
//   node test/browser/run.mjs a b       exactly those suites, by file name
//   node test/browser/run.mjs --not a b every suite except those
//
// The last two are for CI, which runs the suites in parallel jobs. Its last
// shard says what the others are and takes the rest with `--not`, so a suite
// added here lands in a shard without anyone having to remember to list it.
//
import { run } from "./harness.mjs"
import * as study from "./study.mjs"
import * as offline from "./offline.mjs"
import * as speech from "./speech.mjs"
import * as storage from "./storage.mjs"
import * as production from "./production.mjs"
import * as progress from "./progress.mjs"
import * as language from "./language.mjs"
import * as sync from "./sync.mjs"
import * as milestone from "./milestone.mjs"
import * as verbs from "./verbs.mjs"
import * as notes from "./notes.mjs"
import * as keys from "./keys.mjs"
import * as tabs from "./tabs.mjs"

// Keyed by file as well as title, so `verify -- speech` finds speech.mjs even
// though its title reads differently.
const suites = [
  ["study", study],
  ["offline", offline],
  ["speech", speech],
  ["storage", storage],
  ["production", production],
  ["progress", progress],
  ["language", language],
  ["sync", sync],
  ["milestone", milestone],
  ["verbs", verbs],
  ["notes", notes],
  ["keys", keys],
  ["tabs", tabs],
]

const args = process.argv.slice(2)
const invert = args[0] === "--not"
const filters = (invert ? args.slice(1) : args).map(f => f.toLowerCase())
// One plain filter keeps the old loose match, by file or by title. Several, or
// `--not`, are exact file names: "progress" is also in the title of the sync
// suite, and a shard that quietly ran it twice would be the slow one.
const loose = !invert && filters.length === 1
const matches = ([key, s], f) =>
  loose ? key.includes(f) || s.name.toLowerCase().includes(f) : key === f
const chosen = filters.length
  ? suites.filter(entry => filters.some(f => matches(entry, f)) !== invert)
  : suites

// Every filter has to find something, or a typo in a shard runs less than it
// was meant to and says nothing.
const unmatched = filters.filter(f => !suites.some(entry => matches(entry, f)))
if (unmatched.length || !chosen.length) {
  console.error(`No suite matching "${unmatched.join('", "') || args.join(" ")}". Available:`)
  for (const [key, s] of suites) console.error(`  ${key.padEnd(12)} ${s.name}`)
  process.exit(1)
}

// A suite that throws gets one more go; one that fails a check does not. The
// only flake seen so far is Puppeteer's "detached Frame" under load, which
// throws, and passes when the suite runs alone. A check that fails is the app
// being wrong, and retrying it would teach people to ignore red. The retry is
// printed, so a suite that keeps needing one is visible rather than hidden.
let failed = 0
for (const [, suite] of chosen) {
  let result = await run(suite.name, suite.default)
  if (result.threw) {
    console.log(`  ↻ retrying "${suite.name}" once, since it threw`)
    result = await run(suite.name, suite.default)
  }
  failed += result.failed
}

console.log(failed
  ? `\n${failed} check(s) failed`
  : `\nAll ${chosen.length} suite${chosen.length === 1 ? "" : "s"} passed`)
process.exit(failed ? 1 : 0)
