// A worktree per piece of work, so two people on one machine do not share a
// build.
//
//   npm run worktree <name>
//
// Makes .claude/worktrees/<name> and installs into it. The path is printed;
// work there.
//
// <name> is a branch. If it already exists - here or on the remote - the
// worktree is put on it, which is how you review someone's branch without
// disturbing your own checkout. Otherwise it is created off origin/main. What
// it did is printed, since that is the part worth not guessing at.
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
  console.error("usage: npm run worktree <branch>   (lowercase, hyphens)")
  console.error("  an existing branch is checked out; a new one is cut from origin/main")
  process.exit(1)
}

// Against the repository's root, not the current directory. Run from inside
// a worktree - which is where you will be, once you are following the
// convention - a relative path nests one worktree inside another.
const root = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { encoding: "utf-8" }).trim()
const dir = path.join(path.dirname(root), ".claude", "worktrees", name)
const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { stdio: "inherit", ...opts })

if (fs.existsSync(dir)) {
  console.error(`x ${dir} already exists. Remove it with \`git worktree remove ${dir}\`, or pick another name.`)
  process.exit(1)
}

run("git", ["fetch", "--quiet", "origin"])

const exists = ref => {
  try {
    execFileSync("git", ["rev-parse", "--verify", "--quiet", ref], { stdio: "ignore" })
    return true
  } catch {
    return false
  }
}

// Refuse early and say why. Git's own message for this names a path rather
// than the branch, which is the wrong end to be told about.
const heldBy = execFileSync("git", ["worktree", "list", "--porcelain"], { encoding: "utf-8" })
if (new RegExp(`^branch refs/heads/${name}$`, "m").test(heldBy)) {
  console.error(`x ${name} is already checked out in another worktree. \`git worktree list\` says where.`)
  process.exit(1)
}

if (exists(`refs/heads/${name}`)) {
  console.log(`${name} exists here — putting a worktree on it`)
  run("git", ["worktree", "add", dir, name])
} else if (exists(`refs/remotes/origin/${name}`)) {
  console.log(`${name} exists on the remote — tracking it`)
  run("git", ["worktree", "add", "--track", "-b", name, dir, `origin/${name}`])
} else {
  // Off origin/main rather than whatever this checkout is on: branch
  // protection requires a branch to be up to date before it merges, and
  // starting behind only means rebasing later.
  console.log(`${name} is new — cutting it from origin/main`)
  run("git", ["worktree", "add", "-b", name, dir, "origin/main"])
}

console.log(`\ninstalling into ${dir} …`)
run("npm", ["ci"], { cwd: dir })

console.log(`
  cd ${dir}

Its own public/ and output/, so a build here disturbs nobody. Remove it when
you are done with the branch:

  git worktree remove ${dir}
`)
