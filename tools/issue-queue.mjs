// The issue queue, derived from labels rather than written down anywhere. See
// `npm run issues -- --queue`.
//
// A ranked list kept in a file goes stale, and one kept in a conversation is
// lost. Labels are set where issues are already touched, by whoever files or
// answers one, so the list is a function of them and nothing has to be kept in
// step by hand.
//
//   priority: next | soon | later   exactly one on every open issue, or `parked`
//   parked                          not now; the issue says what would change that
//   needs-you                       waiting on the maintainer, whatever its tier
//   blocked                         waiting on another issue; a comment says which
//
// Pure, and given the issues and the open pull requests rather than fetching
// them, so test/queue.mjs can say what it does with a bad label without GitHub.

export const TIERS = [
  ["next", "priority: next"],
  ["soon", "priority: soon"],
  ["later", "priority: later"],
]

const DAY = 86400000
const names = i => (i.labels ?? []).map(l => l.name)

export const buildQueue = (issues, prs, now = new Date()) => {
  // Which open pull requests say they close which issue. An issue with one is
  // being worked, so it is not offered as the next thing to pick up.
  const inFlight = new Map()
  for (const p of prs) {
    for (const r of p.closingIssuesReferences ?? []) {
      inFlight.set(r.number, [...(inFlight.get(r.number) ?? []), p.number])
    }
  }

  const row = (i, tier) => ({
    number: i.number,
    title: i.title,
    tier,
    age: Math.floor((now - new Date(i.createdAt)) / DAY),
    blocked: names(i).includes("blocked"),
    inFlight: inFlight.get(i.number) ?? [],
  })

  const out = {
    needsYou: [],
    tiers: { next: [], soon: [], later: [] },
    parked: [],
    untriaged: [],
    problems: [],
  }

  for (const i of issues) {
    const ls = names(i)
    const tiers = TIERS.filter(([, label]) => ls.includes(label)).map(([t]) => t)
    const parked = ls.includes("parked")

    // A contradiction is reported and the issue is left out of the lists, since
    // placing it anywhere would be a guess and it should be noticed.
    if (tiers.length > 1) {
      out.problems.push({ number: i.number, title: i.title, why: `has more than one priority label (${tiers.join(", ")})` })
      continue
    }
    if (parked && tiers.length) {
      out.problems.push({ number: i.number, title: i.title, why: `is both parked and priority: ${tiers[0]}` })
      continue
    }
    if (!parked && !tiers.length) {
      out.untriaged.push(row(i, null))
      continue
    }

    const r = row(i, parked ? "parked" : tiers[0])
    if (ls.includes("needs-you")) out.needsYou.push(r)
    else if (parked) out.parked.push(r)
    else out.tiers[tiers[0]].push(r)
  }

  const oldest = (a, b) => b.age - a.age || a.number - b.number
  const ready = r => !r.blocked && !r.inFlight.length
  // Ready first, since that is what can be picked up, then the rest, each
  // oldest first. A blocked issue older than a ready one still comes after it.
  const byReadiness = (a, b) => (ready(b) - ready(a)) || oldest(a, b)

  for (const t of Object.keys(out.tiers)) out.tiers[t].sort(byReadiness)
  const rank = r => ["next", "soon", "later", "parked"].indexOf(r.tier)
  out.needsYou.sort((a, b) => rank(a) - rank(b) || oldest(a, b))
  out.parked.sort(oldest)
  out.untriaged.sort(oldest)
  return out
}

const flags = r =>
  (r.blocked ? "  [blocked]" : "") + (r.inFlight.length ? `  [PR ${r.inFlight.map(n => "#" + n).join(", ")}]` : "")

export const renderQueue = q => {
  const line = (r, withTier) =>
    `  #${String(r.number).padEnd(4)} ${withTier ? r.tier.padEnd(7) : ""}${String(r.age + "d").padStart(4)}  ${r.title.slice(0, 66)}${flags(r)}`
  const section = (heading, rows, withTier = false) =>
    rows.length ? [`${heading} (${rows.length})`, ...rows.map(r => line(r, withTier)), ""] : []

  const total = q.needsYou.length + Object.values(q.tiers).flat().length + q.parked.length
    + q.untriaged.length + q.problems.length

  return [
    "",
    `${total} open issues`,
    "",
    ...(q.needsYou.length
      ? section("Needs you: a decision, or something only the maintainer can do", q.needsYou, true)
      : ["Needs you: nothing", ""]),
    ...section("Next", q.tiers.next),
    ...section("Soon", q.tiers.soon),
    ...section("Later", q.tiers.later),
    ...section("Parked", q.parked),
    ...section("Untriaged: give each a priority label, or `parked`", q.untriaged),
    ...(q.problems.length
      ? ["Problems", ...q.problems.map(p => `  #${p.number}  ${p.why}`), ""]
      : []),
  ].join("\n")
}
