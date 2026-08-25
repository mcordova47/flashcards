export const name = "Installable and offline"

export default async ({ check, open }) => {
  const page = await open()
  await page.waitForSelector(".prompt")

  const manifest = await page.evaluate(async () => {
    const link = document.querySelector('link[rel="manifest"]')
    return link ? await (await fetch(link.href)).json() : null
  })
  check("the manifest is linked and parses", manifest?.name, "Mil Palabras")
  check("it installs standalone", manifest?.display, "standalone")
  check("with a maskable icon", manifest.icons.some(i => i.purpose === "maskable"), true)
  check("and the sizes a launcher wants",
    manifest.icons.filter(i => i.purpose === "any").map(i => i.sizes).sort(), ["192x192", "512x512"])
  check("the standard capability meta is present",
    await page.$eval('meta[name="mobile-web-app-capable"]', e => e.content), "yes")
  check("and an apple touch icon for iOS",
    await page.$eval('link[rel="apple-touch-icon"]', e => e.getAttribute("href")),
    "/assets/images/apple-touch-icon.png")

  await page.waitForFunction(() => navigator.serviceWorker.controller !== null, { timeout: 20000 })
  const cache = await page.evaluate(async () => {
    const names = await caches.keys()
    const held = await (await caches.open(names[0])).keys()
    return { name: names[0], urls: held.map(r => new URL(r.url).pathname) }
  })
  check("one cache, stamped with the build", cache.name.startsWith("mil-palabras-"), true)
  check("holding the app shell",
    ["/", "/index.js", "/assets/stylesheets/theme.css"].every(u => cache.urls.includes(u)), true)

  await page.tap(".card")
  await page.tap(".got-it")
  check("a card was graded online", await page.text(".prompt"), "querer")

  await page.setOfflineMode(true)
  await page.reload({ waitUntil: "domcontentloaded" })
  await page.waitForSelector(".prompt", { timeout: 20000 })
  check("the app loads with no network", await page.text(".prompt"), "querer")
  check("styles survived", await page.$eval(".card", e => getComputedStyle(e).cursor), "pointer")
  await page.tap(".card")
  check("flipping works offline", await page.text(".answer"), "to want")
  await page.tap(".got-it")
  check("grading works offline", await page.text(".prompt"), "este")
  await page.reload({ waitUntil: "domcontentloaded" })
  await page.waitForSelector(".prompt")
  check("offline progress persisted", await page.text(".prompt"), "este")

  await page.setOfflineMode(false)
  await page.reload({ waitUntil: "networkidle0" })
  await page.waitForSelector(".prompt")
  check("and it recovers when the network returns", await page.text(".prompt"), "este")
  check("no page errors", page.errors, [])
}
