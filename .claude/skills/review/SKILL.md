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

**Then merge `origin/main` in and test that.** `main` is protected with
`strict`, so the merge is what will land, and two branches that each pass
alone can break together. Say so if the merge is not clean.

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

**A comment on a line blocks the merge.** `required_conversation_resolution`
is on, so "non-blocking nit" is not something you can actually offer. Either
it is worth stopping for and goes in a thread, or it is not and goes in the
summary.
