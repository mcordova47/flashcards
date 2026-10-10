// The issue queue's rules, on made-up issues: how it orders, and what it does
// with a label that contradicts another. See tools/issue-queue.mjs.
//
//   node test/queue.mjs
//
// Pure, so no GitHub and no build.

import { buildQueue, renderQueue } from "../tools/issue-queue.mjs"

let failed = 0
const stable = v => JSON.stringify(v)
const check = (label, actual, expected) => {
  const ok = stable(actual) === stable(expected)
  if (!ok) failed++
  console.log(`  ${ok ? "✓" : "✗"} ${label}`)
  if (!ok) console.log(`      expected ${stable(expected)}\n      got      ${stable(actual)}`)
}

const NOW = new Date("2026-10-10T12:00:00Z")
const ago = d => new Date(NOW - d * 86400000).toISOString()
const issue = (number, days, ...labels) =>
  ({ number, title: `issue ${number}`, createdAt: ago(days), labels: labels.map(name => ({ name })) })
const numbers = rows => rows.map(r => r.number)
const q = (issues, prs = []) => buildQueue(issues, prs, NOW)

console.log("\nThe issue queue")

{
  const r = q([
    issue(5, 10, "priority: next"),
    issue(3, 20, "priority: next"),
    issue(9, 30, "priority: next", "blocked"),
  ])
  check("within a tier, what can be picked up comes first, oldest first", numbers(r.tiers.next).slice(0, 2), [3, 5])
  check("and a blocked issue comes after, however old", numbers(r.tiers.next), [3, 5, 9])
  check("a blocked issue says so", r.tiers.next[2].blocked, true)
}

{
  const r = q([
    issue(1, 5, "priority: soon"),
    issue(7, 50, "priority: soon", "needs-you"),
    issue(2, 40, "priority: next", "needs-you"),
  ])
  check("a needs-you issue is not offered as something to pick up", numbers(r.tiers.soon), [1])
  check("it is listed first, by tier and then age", numbers(r.needsYou), [2, 7])
  check("with the tier it would be in", r.needsYou.map(x => x.tier), ["next", "soon"])
}

{
  const r = q([issue(4, 9, "priority: soon"), issue(6, 3, "priority: soon")], [
    { number: 50, closingIssuesReferences: [{ number: 4 }] },
  ])
  check("an issue with an open pull request is not offered", numbers(r.tiers.soon), [6, 4])
  check("and says which", r.tiers.soon[1].inFlight, [50])
}

{
  const r = q([issue(8, 2, "parked"), issue(10, 4, "priority: later"), issue(11, 6)])
  check("parked issues are kept apart from the tiers", [numbers(r.parked), numbers(r.tiers.later)], [[8], [10]])
  check("an issue with neither a priority nor parked is untriaged", numbers(r.untriaged), [11])
}

{
  const r = q([
    issue(20, 1, "priority: next", "priority: soon"),
    issue(21, 1, "parked", "priority: later"),
    issue(22, 1, "priority: next"),
  ])
  check("two priority labels are a problem and not a guess", r.problems.map(p => p.number), [20, 21])
  check("and the issue is left out of every list", [numbers(r.tiers.next), numbers(r.tiers.soon), numbers(r.parked)], [[22], [], []])
}

{
  const r = q([issue(30, 1, "bug", "priority: next"), issue(31, 1, "enhancement")])
  check("labels the queue does not know are ignored", [numbers(r.tiers.next), numbers(r.untriaged)], [[30], [31]])
  check("nothing at all is fine", numbers(q([]).tiers.next), [])
}

{
  const text = renderQueue(q([
    issue(1, 3, "priority: next", "blocked"),
    issue(2, 3, "priority: soon", "needs-you"),
    issue(3, 3),
  ]))
  check("the text leads with what needs the maintainer", text.indexOf("Needs you") < text.indexOf("Next"), true)
  check("marks a blocked issue", /#1\s.*\[blocked\]/.test(text), true)
  check("flags the untriaged", text.includes("Untriaged"), true)
  check("says when nothing needs the maintainer", renderQueue(q([issue(1, 1, "priority: next")])).includes("Needs you: nothing"), true)
}

console.log(failed ? `\n  ${failed} failed\n` : "\n  all passed\n")
process.exit(failed ? 1 : 0)
