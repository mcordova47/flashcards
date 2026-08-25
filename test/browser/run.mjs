// Runs the browser suites against the built site.
//
//   npm run verify              every suite
//   npm run verify -- speech    just the ones matching
//
import { run } from "./harness.mjs"
import * as study from "./study.mjs"
import * as offline from "./offline.mjs"
import * as speech from "./speech.mjs"
import * as storage from "./storage.mjs"
import * as production from "./production.mjs"
import * as progress from "./progress.mjs"

// Keyed by file as well as title, so `verify -- speech` finds speech.mjs even
// though its title reads differently.
const suites = [
  ["study", study],
  ["offline", offline],
  ["speech", speech],
  ["storage", storage],
  ["production", production],
  ["progress", progress],
]

const filter = process.argv[2]?.toLowerCase()
const chosen = filter
  ? suites.filter(([key, s]) => key.includes(filter) || s.name.toLowerCase().includes(filter))
  : suites

if (!chosen.length) {
  console.error(`No suite matching "${process.argv[2]}". Available:`)
  for (const [key, s] of suites) console.error(`  ${key.padEnd(12)} ${s.name}`)
  process.exit(1)
}

let failed = 0
for (const [, suite] of chosen) failed += await run(suite.name, suite.default)

console.log(failed
  ? `\n${failed} check(s) failed`
  : `\nAll ${chosen.length} suite${chosen.length === 1 ? "" : "s"} passed`)
process.exit(failed ? 1 : 0)
