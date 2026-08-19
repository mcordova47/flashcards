import { build } from "esbuild"
import crypto from "crypto"
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

// Stamp the service worker's cache name with a hash of what it caches, so a
// deploy invalidates the old cache and nothing else does.
const hash = crypto.createHash("sha256")
for (const file of ["./public/index.js", "./public/index.html", "./public/assets/stylesheets/theme.css"]) {
  hash.update(fs.readFileSync(file))
}
const version = hash.digest("hex").slice(0, 12)
fs.writeFileSync("./public/sw.js", fs.readFileSync("sw.js", "utf-8").replace("__VERSION__", version))

console.log(`✅ Build complete! (service worker cache: ${version})`)
