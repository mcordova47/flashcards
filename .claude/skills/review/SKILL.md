---
name: review
description: Review a pull request in this repository against its own claims. Use when asked to review, check or look over a PR by number.
---

# Reviewing a pull request

`$ARGUMENTS` is the pull request number.

Read `CONTRIBUTING.md` first, **Prove the claims** especially. This is how to
apply it to someone else's branch.

## Somewhere to stand

The shared checkout is usually on somebody's branch with their work in it.
Build there and you land under their test run.

```
npm run worktree <their-branch>
```

If they still hold it — `git worktree list` will say — take a detached one
instead, which disturbs nothing:

```
git worktree add --detach .claude/worktrees/review-<n> $(git rev-parse origin/<their-branch>)
```

## Let CI run the gate

**Do not run `npm run verify` over someone else's branch.** CI already has:
the `pull_request` trigger builds and tests the *merge result*, and `strict`
means a branch cannot land while it is behind, so a green check is a green
merge. Repeating it costs four minutes and tells you what `gh pr checks <n>`
tells you in one second.

```
gh pr checks <n>
```

Two cases where that is not the whole answer, and neither is "run everything":

- **The branch is behind `main`.** Then CI's run is against an older merge
  base. Say so and let the update re-run it. Testing the merge yourself only
  learns what CI will learn anyway.
- **The pull request changes the workflow, or what the workflow runs.** Then
  the green check was produced by the old one, and what it proves is a
  question rather than an answer.

The author runs the gate before proposing, per `CONTRIBUTING.md`, so that a
red branch never reaches a reviewer. The reviewer does not run it again. That
asymmetry is the point: you are here to check what CI cannot.

## The claims are the work

A pull request here ends with *how each claim was checked*. **Re-run them.**
Not because anyone is lying — nobody has been — but because the honest
mistake is the common one. In this repository, re-running has found: a second
caller of a changed function that no suite covers, a quote reported as
missing that was there all along, and a spec passing for a reason its author
did not intend.

**Derive the claim yourself rather than reading their code for it.** If they
say a generator refuses 23 cases, compute 23 from the CSV. If they say a pool
has 40 exercises, count it from the bank. A reimplementation that agrees is
evidence; reading the implementation that produced the number is not.

**Plant the failure.** Take the guard out and watch the test fail. Three tests
in this repository have passed with the thing they tested removed, all three
written in good faith. A test nobody has seen fail is a comment.

**Run only what you planted against.** `npm test` is seconds. One browser
suite is `node test/browser/run.mjs <name>` and about thirty. Ten suites is
four minutes and answers a question nobody asked — you are not checking
whether the branch is green, CI did that; you are checking whether one test
can fail.

## Read the content

Most of this repository is Spanish, and no tool can say whether a sentence
means what its row claims. The checks prove a form is the one the table gives;
they cannot see an imperative nobody teaches, a possessive pointing the wrong
way, or a prompt that asks for one thing while the rubric wants another. Every
one of those was found by reading, and none by running anything.

If the change touches a corpus, read the corpus. All of it.

## What to say

Order by what matters, and separate **this is wrong** from **I checked this
and it is fine**. The second is worth saying: it tells the author what was
looked at.

Say what is good, and why, where the work beat what was asked of it. That has
happened more often than not, and an author who only hears about faults learns
less than one who hears which of their judgements was better than the issue's.

**Own what is yours.** Where the issue was wrong, say the issue was wrong, and
edit it — the reviewer edits, per `CONTRIBUTING.md`, and the author does not.

## What to do with what you found

Every finding ends in exactly one of three places, and **you decide which**.
There is no "not blocking" section and no "follow-up". The first leaves the
maintainer guessing which things matter. The second is a promise nobody holds:
nothing happens after a pull request merges unless a person coordinates it,
and the maintainer's attention is the scarce thing here, not CI minutes. Decide
whatever can be decided.

**Fix it in this pull request.** When the finding is about what this change does
or claims, and the right fix is clear. You decide that it is a fix and say what
to change and why, and **the author makes the commit**: you do not push to their
branch. Another round of CI costs minutes; a fix put off costs a person.

**File a new issue.** When it is real but is not this change's to fix: it was
already true before the change, it is a different deliverable, or it needs a
decision or data nobody here has. File it yourself, with the reasoning
(`CONTRIBUTING.md`, *Issues carry the reasoning*), and link it from the review.
An issue is something `/issue` can pick up. A sentence in a comment is not.
**Tell the maintainer afterwards**, in your reply: each issue's number and title.
You file without asking, so the telling is what keeps that safe.

**Ignore it.** When it is wrong, already decided, or not worth the change. Say
so in a line, with the reason, so nobody raises it again. *I checked this and
it is fine* is this disposition and is worth saying.

### Which one

A finding about what the change touches or claims, with a clear fix, is a fix
here. A finding about something it did not touch is an issue, and so is
anything that would be a different deliverable: a fix to code the pull request
never changed does not go in as a commit, because one commit is one deliverable.

**Ask the maintainer only when the answer depends on something you cannot see.**
That is a change to what gets built, which is the line `/issue` already draws
between *the same thing either way* and *something materially different*, or a
matter of taste with no right answer. Put those first, under **Needs you**.
A review whose **Needs you** is empty is the goal.

### Leave the fixes for the author

Put every fix-here item in **one place**: a single review comment on the pull
request (`gh pr review <n> --comment --body-file <file>`), as a numbered list,
each saying what to change and why. Not a thread per item. A thread is for
something that cannot be said without pointing at a line, and
`required_conversation_resolution` is on, so each open one is a click for the
maintainer. If you do open one, the author resolves it after fixing it.

**Say whether it needs another look.** *No re-review needed* for fixes the author
can check themselves. *Re-review after* only when a fix changes something you
verified. That is your decision, not the maintainer's.

The maintainer tells the author that a review is waiting. Make that one line
they can paste.

### How to end

With a short table, and then **one** verdict.

| finding | disposition | where |
| --- | --- | --- |
| the gate ignores a blank row | fix | item 1 of the review |
| the same fault in an untouched module | issue | #140 |
| a `TODO` the author left | ignore | already tracked in #98 |

- **Ready to merge.** No fix items, nothing needs the maintainer, checks are
  green. Queue it yourself: `gh pr merge <n> --rebase --auto`, and say so.
- **Fix, then merge.** Fix items, no re-review needed. Do **not** queue
  auto-merge: it merges the moment checks pass, which would be before the
  fixes. The author makes them, waits for green, and queues it.
- **Fix, then re-review.** The author makes the fixes and says so. Nothing is
  queued until you have looked again.
- **Needs you.** The list, first. Nothing is queued while it is open.

Then tell the maintainer: the verdict, each issue you filed with its number and
title, and the one line to paste to the author.

If auto-merge stalls because the branch is behind `main`, it needs a rebase;
`CONTRIBUTING.md` says how.
