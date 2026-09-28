# Working on this

Several people and several agents work here at once. These are the conventions
that make that survivable. The README says how the app works; this says how
changes to it get made.

## Branch, pull request, merge

`main` is protected: the `data` and `browser` checks must pass, and a branch
must be up to date with main before it merges. Everything arrives as a pull
request, which is what lets two pieces of work proceed without silently
landing on top of each other.

The protection does not apply to admins, so the repository owner can still
push directly. That is an escape hatch and not the workflow — a direct push is
how two agents end up editing the same file with neither knowing.

CI runs on the pull request, and on `main` afterwards. Those answer different
questions: the pull request tests the **merge result**, which no branch
contains, and `main` catches anything that gets in another way. Two branches
that each pass alone can break together — the drift check especially, since a
regenerated module is only stale relative to whatever else landed.

## One commit, one deliverable

Not one commit per session and not one per file. A refactor that enables a
feature is its own commit, landing first, so that it can be read and reverted
on its own. This has been done three times — the scheduler, the payload and
`Stats` all came off the card model separately from whatever wanted them to.

Where a change is mechanical and its output should be unchanged, say so in the
message and prove it: regenerate and diff, or run the tool before and after
and compare. "No behaviour change" is a claim, and it is cheap to check.

## Commit messages say why

The diff already says what. A message is worth writing when it records a
decision, an alternative that was rejected, or a thing that was surprising.
`git log` here is the closest thing to a design history, and it is used as one.

## Before you propose it

```
npm run verify     # the data checks, the build, and the browser suites
npm test           # the pure core, in seconds
```

`verify` is the gate. If a browser suite throws it is retried once — that is
for Puppeteer's `detached Frame` under load, which is real. A suite that fails
a *check* is not retried, and that is the app being wrong.

If you changed a CSV, run `npm run sync` and commit what it writes, or CI will
refuse the push and tell you to.

## Tests that prove something

A regression test that passes without the fix proves nothing. This has caught
us twice: a guard against a double-tap, and a keyboard fix that autofocus was
already covering. **Remove the fix, watch the test fail, put it back.** It
takes a minute and it is the difference between a test and a comment.

The same goes for a checker rule: plant the thing it refuses and watch it
refuse.

## Issues carry the reasoning

An issue is where a decision gets argued and written down, so that the next
person — or the next agent — starts from the conclusion rather than the
question. When a review changes one, the issue gets edited, not just replied
to: a correction below a wrong example is a trap for whoever reads it next.

Where an issue turns out to be wrong, say so in it. Several here carry a
"settled after review" section doing exactly that.

## Review is a separate pass

Work gets reviewed by someone who did not write it, and the review checks
claims rather than reading them. Regenerate the thing that is supposed to be
byte-identical. Plant the failure the new rule is supposed to catch. Run the
one caller that the test suite does not cover.
