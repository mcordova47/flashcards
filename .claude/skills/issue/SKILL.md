---
name: issue
description: Pick up a GitHub issue in this repository and take it to a pull request. Use when asked to work on, implement, or start an issue by number.
---

# Working an issue

`$ARGUMENTS` is the issue number.

## Before you write anything

**Read the issue, then read `CONTRIBUTING.md`.** The second is the whole of how
work is made here and is not repeated below.

```
gh issue view <n> --comments
```

**`--comments`, always.** Corrections live in comments here by design — the
rule below is that you do not edit the issue body, so everything learned after
an issue was written is underneath it. The body alone is the stale half, and
`gh issue view <n>` does not show the rest.

This is not hypothetical. #3's body describes building a card face that
already ships and gating sentences on a vocabulary rule its own comment
disproved by measurement. #62's body specifies a purge command that its
comments amend precisely so it cannot delete the only copy of a note. Either
one, read without its comments, produces confident work against a spec that
was corrected weeks or hours earlier.

**Then argue with it.** Issues here carry reasoning rather than requirements,
and the reasoning has been wrong more than once — arithmetic that did not hold,
a rule that contradicted its own worked example, a constraint no checker could
actually enforce. Every one of those was caught by whoever picked the issue up,
not by whoever wrote it.

**Where the argument goes depends on what it would change.**

If you would build the *same thing* either way — the issue is stale, its
reasoning is loose, a step is unnecessary, the whole thing is not worth doing —
then build it your way and **put the disagreement in the pull request**. That
is where it can be read against the code it is about, and it does not leave you
waiting on an answer.

If you would build something *materially different* — different data, a
different item model, a different shape — say so first, in a comment on the
issue, and wait. Authoring forty rows against the wrong rule and redoing them
is the expensive failure; every disagreement that has mattered here was of this
kind.

Either way: **do not edit the issue body.** Whoever reviews decides and edits
it afterwards, because a correction can itself be wrong, and because editing
replaces the whole body, so two of you at once would clobber each other.

A faithful implementation of a flawed issue costs more than an argument.

**If the issue has open questions**, ask whether they are yours to answer or to
bring back. Several here are deliberately left open and it is not always
obvious which.

## Doing it

Work in a worktree of your own:

```
npm run worktree <short-name>
```

It branches off `origin/main`, installs, and prints a path to work in. Not
optional politeness — the shared checkout has one `public/` and one `output/`
between everyone in it, so a build of yours lands under someone else's test
run. `main` is protected and direct pushes are refused.

Follow `CONTRIBUTING.md`: one commit per deliverable, enabling refactors first,
`npm run verify` and `npm test` before you propose anything.

## Proving it

Do what **Prove the claims** in `CONTRIBUTING.md` says, and take it seriously:
it is the part most often skipped, and skipped honestly. Nobody here has yet
asserted something they knew to be untrue; several have asserted something they
had not checked.

## Handing it over

Open a pull request. In the description:

- what changed, file by file
- anything in the issue you disagreed with, and what you did instead
- anything you did not do. Each item is **done, filed, or dropped**: *filed* means
  you opened the issue yourself and put its number here, *dropped* means a
  reason. A bare "left undone" is a loose end nobody will pick up, because
  nothing happens after a merge unless someone coordinates it
- **for each claim, how you checked it**

Tell the maintainer afterwards which issues you filed, with numbers and titles.
An issue you file gets **exactly one** `priority:` label, or `parked`, and
`needs-you` if its next step is the maintainer's (`CONTRIBUTING.md`, *What to do
next*).

Then say so, and stop. Someone who did not write it reviews it.

## When a review is left for you

You are told a review is waiting. Read it (`gh pr view <n> --comments`, and the
review itself).

- **Carry out its fix items, all of them and only them.** Do not widen the change.
  Its issue items and ignore items need nothing from you.
- **Say how you checked each fix**, in a comment on the pull request.
- **If you think an item is wrong, say so there and stop.** Do not skip it
  silently. That makes it a question for the maintainer.
- Push, and wait for `gh pr checks <n>` to go green.
- Then do what the verdict says. **Fix, then merge:** queue
  `gh pr merge <n> --rebase --auto`. **Fix, then re-review:** say the fixes are
  done and stop. If you opened or were handed a thread, resolve it once fixed.
