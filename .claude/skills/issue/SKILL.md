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
gh issue view <n>
```

**Then argue with it.** Issues here carry reasoning rather than requirements,
and the reasoning has been wrong more than once — arithmetic that did not hold,
a rule that contradicted its own worked example, a constraint no checker could
actually enforce. Every one of those was caught by whoever picked the issue up,
not by whoever wrote it.

So before building: say what you think is wrong, or say that it holds. **Say it
in a comment on the issue — do not edit the body.** Whoever reviews decides
whether you are right and edits it if you are, because a correction can itself
be wrong and because editing replaces the whole body, so two of you at once
would clobber each other.

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
- anything left undone, and why
- **for each claim, how you checked it**

Then say so, and stop. Someone who did not write it reviews it.
