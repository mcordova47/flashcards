// A worktree per piece of work, so two people on one machine do not share a
// build.
//
//   npm run worktree <name>
//
// Makes .claude/worktrees/<name> on a new branch off origin/main and installs
// into it. The path is printed; work there.
//
// Not tidiness. `public/` is written by the build and read by the browser
// harness, and `output/` is the PureScript build - both are gitignored, so in
// one shared checkout they are one copy shared by everyone in it. Two agents
// running `npm run verify` at once have one's build landing under the other's
// test run, and the result looks like a flaky suite rather than a collision.
//
// Costs about 320MB a worktree, nearly all of it node_modules and output.

import { execFileSync } from "child_process"
import fs from "fs"
import path from "path"

const name = process.argv[2]
if (!name || !/^[a-z][a-z0-9-]*$/.test(name)) {
  console.error("usage: npm run worktree <name>   (lowercase, hyphens)")
  process.exit(1)
}

const dir = path.join(".claude", "worktrees", name)
const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { stdio: "inherit", ...opts })

if (fs.existsSync(dir)) {
  console.error(`x ${dir} already exists. Remove it with \`git worktree remove ${dir}\`, or pick another name.`)
  process.exit(1)
}

// Off the current origin/main rather than whatever this checkout is on:
// branch protection requires a branch to be up to date before it merges, and
// starting behind only means rebasing later.
run("git", ["fetch", "--quiet", "origin", "main"])
run("git", ["worktree", "add", "-b", name, dir, "origin/main"])

console.log(`\ninstalling into ${dir} …`)
run("npm", ["ci"], { cwd: dir })

console.log(`
  cd ${dir}

Its own public/ and output/, so a build here disturbs nobody. Remove it when
the branch has merged:

  git worktree remove ${dir}
`)
