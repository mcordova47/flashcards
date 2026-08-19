import * as esbuild from "esbuild"
import fs from "fs"

const ctx = await esbuild.context({
  entryPoints: ["./output/EntryPoints.Index/index.js"],
  outfile: "./public/index.js",
  bundle: true,
  format: "iife",
  globalName: "Main",
  sourcemap: true,
})

fs.cpSync("assets", "./public/assets", { recursive: true })
fs.cpSync("index.html", "./public/index.html")

// A fixed cache name in dev: network-first means a stale cache never wins
// anyway, and a churning name would just thrash storage on every rebuild.
fs.writeFileSync("./public/sw.js", fs.readFileSync("sw.js", "utf-8").replace("__VERSION__", "dev"))

await ctx.watch()
await ctx.serve({ servedir: "./public", port: 8000 })

console.log("👀 Watching for changes and serving at http://localhost:8000")
