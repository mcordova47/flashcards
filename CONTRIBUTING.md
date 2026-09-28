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

## A worktree each

```
npm run worktree <branch>
```

Makes `.claude/worktrees/<branch>`, installs into it, and prints the path.
Work there, not in the shared checkout.

A branch that already exists — here or on the remote — is checked out, which
is how you read someone else's work without disturbing your own. One that does
not is cut from `origin/main`. It says which it did.

**This is about correctness, not tidiness.** `public/` is written by the build
and read by the browser harness; `output/` is the PureScript build. Both are
gitignored, which means that in one shared checkout they are *one copy shared
by everyone working in it*. Two people running `npm run verify` at once have
one's build landing underneath the other's test run, and the result looks like
a flaky suite rather than a collision.

It also removes the footgun of a shared `HEAD`. Committing onto somebody
else's branch because you did not check what you were on has happened twice
here, both times by the one person whose pushes the branch protection does not
stop.

About 320MB each, nearly all `node_modules` and `output`. Remove one when its
branch has merged:

```
git worktree remove .claude/worktrees/<name>
```

## The stash you must not touch

**The stash stack is shared across every worktree of a repository**, which the
separate checkouts do not fix.

A bare `git stash` followed by `git stash pop` can therefore take someone
else's work, and has nearly done so here. Set work aside with a throwaway
commit instead. If you must stash, name it — `git stash push -u -m "<tag>"` —
and restore it by its own SHA with `git stash apply`, not `pop`.

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

## Prove the claims

Every claim in a commit message or a pull request is a thing to check, not a
thing to assert. *No behaviour change*, *the test covers it* and *nothing else
calls this* have each been wrong here, each stated in good faith.

**A regression test that passes without the fix proves nothing.** Remove the
fix, watch the test fail, put it back. This has caught us twice — a guard
against a double tap, and a keyboard fix that autofocus was already masking.
Both tests were written honestly and proved nothing.

**A refactor that should produce identical output can be shown to.** Run the
tool before and after and diff; `git archive HEAD` into a temporary directory
gives you the before without touching the working tree. Regenerate a generated
file and confirm it is byte-identical.

**A new rule in a checker can be planted against.** Put in the thing it is
meant to refuse and watch it refuse.

**A changed signature has callers you have not thought of.** Search for all of
them, including tools and scripts that no test suite runs.

## Issues carry the reasoning

An issue is where a decision gets argued and written down, so that the next
person — or the next agent — starts from the conclusion rather than the
question.

**A disagreement with an issue belongs in the pull request that acts on it**,
where it can be read against the code it is about. One review surface, and the
reasoning ends up in a commit message rather than a comment thread — which is
where `git log` will have it later, and this log is read as a design history.

The exception is a disagreement that changes *what gets built* rather than how:
different data, a different item model, a different shape. Say those before
building, in a comment, and wait. Authoring forty rows against the wrong rule
and redoing them is the expensive failure.

**Either way the finder does not edit the body. Whoever reviews decides, and
edits it.** A correction can itself be wrong, and a comment or a pull request
is cheap to disagree with where an edit is work to undo. And `gh issue edit`
replaces the whole body, so two people correcting one issue at once would
clobber each other without either noticing.

The body does get edited in the end, though, and that part of the original
rule stands: a correction left only in a comment below a wrong example is a
trap for whoever reads the example next. Several issues here carry a "settled
after review" section recording what changed and why, which is what it looks
like once the decision has been made.

## Review is a separate pass

Work gets reviewed by someone who did not write it, and the review checks
claims rather than reading them. `npm run worktree <their-branch>` gives you
somewhere to run it that is not wherever you happened to be standing. Regenerate the thing that is supposed to be
byte-identical. Plant the failure the new rule is supposed to catch. Run the
one caller that the test suite does not cover.
