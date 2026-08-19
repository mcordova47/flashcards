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

await ctx.watch()
await ctx.serve({ servedir: "./public", port: 8000 })

console.log("👀 Watching for changes and serving at http://localhost:8000")
