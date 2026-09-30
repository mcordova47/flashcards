// How the issue tracker is actually moving: the backlog over time, how long
// things take, and which open issues the flow has gone around.
//
//   npm run issues                       the report
//   npm run --silent issues -- --json    the same numbers, machine-readable
//   npm run issues -- --weeks 4          a different window
//
// `--silent` on the JSON because npm prints its own banner to stdout, and
// without it the first thing a parser meets is `> flashcards@1.0.0 issues`.
//
// Reads GitHub through `gh`, so it needs nothing configured that working here
// does not already need. Nothing depends on it and it writes nothing.
//
// It exists because the obvious number is the misleading one. An open count
// going up is not a problem to fix: reviewing well produces issues, so a week
// with good reviews adds more than it closes and looks worse than a week where
// nobody looked at anything. Counting alone cannot tell those apart, which is
// why this reports three things instead.
//
//   1. BACKLOG, so the direction is visible rather than the level. Whether it
//      is 12 or 20 matters much less than whether the last fortnight bent up
//      or down, and a burst from planning an epic looks identical to drift
//      unless you can see it come back down.
//
//   2. LEAD TIME, which is the honest throughput number. It measures issues
//      that finished, so it cannot be gamed by writing more of them, and a
//      median that stays flat while the backlog grows means the growth is
//      intake rather than a slowdown.
//
//   3. OUTLIVED, the one worth acting on. Two obvious signals both fail here.
//      Raw age accuses everything of being stalled in a quiet month. Counting
//      how many newer issues closed past it — the first thing this tool did —
//      fails the opposite way: when most issues close the same day, a
//      three-day-old issue has already been passed by a dozen, and the number
//      measures how fast the repository is rather than whether anything is
//      stuck.
//
//      So an open issue is measured against what closing actually takes here.
//      `outlived` is the share of closed issues whose whole lifetime was
//      shorter than this one has been open already. At 100% nothing that ever
//      closed took this long, and the normal flow is not going to reach it —
//      which is a claim about this repository's own pace, so it holds whether
//      that pace is an hour or a month.
//
// It is not a verdict. #7 scores high and is correctly parked — it says so
// itself. The number says "this will not happen by itself", and the answer is
// sometimes to close it rather than to do it.
//
// GitHub numbers issues and pull requests from one sequence, so an issue's
// number has gaps where pull requests took them. Overtaken counts issues only,
// which is what it should: a pull request is not something that queue-jumped.

import { execFileSync } from "child_process"

const args = process.argv.slice(2)
const asJson = args.includes("--json")
const weeks = Number(args[args.indexOf("--weeks") + 1]) || 8

const gh = a => JSON.parse(execFileSync("gh", a, { encoding: "utf-8", maxBuffer: 32 * 1024 * 1024 }))

const issues = gh([
  "issue", "list",
  "--state", "all",
  "--limit", "500",
  "--json", "number,title,state,createdAt,closedAt",
])

if (!issues.length) {
  console.error("no issues found — is `gh` authenticated for this repository?")
  process.exit(1)
}

const DAY = 86400000
const day = iso => iso.slice(0, 10)
const days = (from, to) => Math.round((new Date(to) - new Date(from)) / DAY)
const now = new Date()

// --- 1. backlog, by day, carried forward -------------------------------------

// Only days something happened produce a row; a week where nothing moved is
// not worth a line. The running total still carries across the gap.
const moved = new Map()
const bump = (d, key) => moved.set(d, { ...{ new: 0, closed: 0 }, ...moved.get(d), [key]: (moved.get(d)?.[key] ?? 0) + 1 })
for (const i of issues) {
  bump(day(i.createdAt), "new")
  if (i.closedAt) bump(day(i.closedAt), "closed")
}

let open = 0
const backlog = [...moved.keys()].sort().map(d => {
  const { new: n, closed: c } = moved.get(d)
  open += n - c
  return { date: d, opened: n, closed: c, open }
})

const since = new Date(now - weeks * 7 * DAY).toISOString().slice(0, 10)
const recent = backlog.filter(r => r.date >= since)

// --- 2. lead time ------------------------------------------------------------

const closed = issues.filter(i => i.closedAt)
const leads = closed.map(i => days(i.createdAt, i.closedAt)).sort((a, b) => a - b)
const median = xs => xs.length ? xs[Math.floor(xs.length / 2)] : null
const lead = {
  closed: leads.length,
  median: median(leads),
  mean: leads.length ? Number((leads.reduce((a, b) => a + b, 0) / leads.length).toFixed(1)) : null,
  max: leads.length ? leads[leads.length - 1] : null,
  sameDay: leads.filter(x => x === 0).length,
  withinThree: leads.filter(x => x <= 3).length,
}

// --- 3. overtaken ------------------------------------------------------------

// For each open issue: how many issues opened after it have already closed.
// Work flowing past something is what stalled looks like, and unlike age it
// does not accuse everything of being stalled in a quiet month.
const closedNumbers = closed.map(i => i.number)

// Against the repository's own pace: what share of everything that closed took
// less time than this has already been open. `leads` is already sorted.
const outlived = age => leads.length ? leads.filter(l => l < age).length / leads.length : 0

const stalled = issues
  .filter(i => i.state === "OPEN")
  .map(i => {
    const age = days(i.createdAt, now)
    return {
      number: i.number,
      title: i.title,
      age,
      outlived: Number(outlived(age).toFixed(2)),
      overtaken: closedNumbers.filter(c => c > i.number).length,
    }
  })
  .sort((a, b) => b.outlived - a.outlived || b.age - a.age)

const report = {
  counted: issues.length,
  open: stalled.length,
  closed: lead.closed,
  backlog: recent,
  lead,
  stalled,
}

if (asJson) {
  console.log(JSON.stringify(report, null, 2))
  process.exit(0)
}

// --- the report --------------------------------------------------------------

const pad = (s, n) => String(s).padEnd(n)
const num = (s, n) => String(s).padStart(n)

console.log(`\n${issues.length} issues — ${report.open} open, ${report.closed} closed\n`)

console.log(`Backlog, last ${weeks === 1 ? "week" : weeks + " weeks"}`)
if (!recent.length) {
  console.log("  nothing opened or closed")
} else {
  const peak = Math.max(...recent.map(r => r.open), 1)
  for (const r of recent) {
    const bar = "█".repeat(Math.max(1, Math.round((r.open / peak) * 24)))
    console.log(`  ${r.date}  ${num("+" + r.opened, 3)} ${num("-" + r.closed, 3)}  ${num(r.open, 3)} ${bar}`)
  }
}

console.log(`\nLead time, over ${lead.closed} closed`)
console.log(`  median ${lead.median}d, mean ${lead.mean}d, longest ${lead.max}d`)
console.log(`  same day ${lead.sameDay}/${lead.closed}, within three ${lead.withinThree}/${lead.closed}`)

// Only the ones the flow has demonstrably not reached. Below this they are
// merely open, which is what open issues are supposed to be.
const STUCK = 0.9
const worth = stalled.filter(s => s.outlived >= STUCK)
console.log(`\nOutlived — open longer than ${STUCK * 100}% of closed issues ever took`)
if (!worth.length) {
  console.log(`  nothing: every open issue is younger than ${STUCK * 100}% of closed lifetimes`)
} else {
  for (const s of worth) {
    const flag = s.outlived === 1 ? "  <- longer than anything" : ""
    console.log(`  ${pad("#" + s.number, 5)} ${num(Math.round(s.outlived * 100) + "%", 4)}  ${num(s.age + "d", 5)}  ${pad(s.title.slice(0, 46), 46)}${flag}`)
  }
}

console.log(`\n${stalled.length - worth.length} other open issue(s) are still inside the normal range.`)
console.log()
