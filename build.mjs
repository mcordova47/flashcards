import { build } from "esbuild"
import fs from "fs"

await build({
  entryPoints: ["./output/EntryPoints.Index/index.js"],
  outfile: "./public/index.js",
  bundle: true,
  format: "iife",
  globalName: "Main",
  sourcemap: true,
  minify: true,
})

fs.cpSync("assets", "./public/assets", { recursive: true })
fs.cpSync("index.html", "./public/index.html")

console.log("✅ Build complete!")
