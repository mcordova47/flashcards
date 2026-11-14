import { wait } from "./harness.mjs"

export const name = "Vocab and Grammar tabs"

const tabs = page =>
  page.$$eval(".tab", es => es.map(e => ({
    tag: e.tagName,
    label: e.querySelector(".tab-label").textContent,
    href: e.getAttribute("href"),
    current: e.getAttribute("aria-current"),
    disabled: e.getAttribute("aria-disabled"),
    on: e.classList.contains("on"),
    off: e.classList.contains("off"),
  })))

// Whether the bar is wholly on screen and underneath the controls, which is
// the claim of "always visible, under the buttons".
const placed = page => page.evaluate(() => {
  const bar = document.querySelector(".tabs").getBoundingClientRect()
  const controls = document.querySelector(".controls")?.getBoundingClientRect()
  return {
    onScreen: bar.top >= 0 && bar.bottom <= innerHeight + 0.5,
    belowControls: controls ? bar.top >= controls.bottom - 0.5 : null,
  }
})

export default async ({ check, open }) => {
  const page = await open()
  await page.waitForSelector(".prompt")
  await wait(300)

  check("the cards show Vocab as the page they are on, and Grammar as a way out",
    await tabs(page),
    [ { tag: "SPAN", label: "Vocab", href: null, current: "page", disabled: null, on: true, off: false }
    , { tag: "A", label: "Grammar", href: "/verbs", current: null, disabled: null, on: false, off: false }
    ])
  check("under the controls and fully on screen while a card is asked",
    await placed(page), { onScreen: true, belowControls: true })

  await page.tap(".card")
  check("and still when it is answered, with two big buttons above",
    [await placed(page), (await page.$$(".grade")).length], [{ onScreen: true, belowControls: true }, 2])

  // The done screen is its own layout.
  for (let i = 0; i < 40 && !(await page.$(".done-title")); i++) {
    if (!(await page.$(".got-it"))) await page.tap(".card")
    await page.tap(".got-it")
    await wait(30)
  }
  check("the done screen has them too", await page.$(".done-title") !== null, true)
  check("in the same place", await placed(page), { onScreen: true, belowControls: true })

  // A tab is a link, like every page change here.
  await Promise.all([page.waitForNavigation({ waitUntil: "networkidle0" }), page.click("a.tab")])
  check("Grammar goes to the drills", new URL(page.url()).pathname, "/verbs")
  await page.waitForSelector(".verb-sentence")
  await wait(300)

  check("which show Grammar as where you are, and Vocab as the way back",
    await tabs(page),
    [ { tag: "A", label: "Vocab", href: "/", current: null, disabled: null, on: false, off: false }
    , { tag: "SPAN", label: "Grammar", href: null, current: "page", disabled: null, on: true, off: false }
    ])
  check("also under the controls", await placed(page), { onScreen: true, belowControls: true })

  await Promise.all([page.waitForNavigation({ waitUntil: "networkidle0" }), page.click("a.tab")])
  check("and Vocab comes back to the cards", new URL(page.url()).pathname, "/")
  check("no page errors", page.errors, [])
  await page.close()

  // --- a language Grammar has nothing for ---
  const german = await open()
  await german.waitForSelector(".prompt")
  await german.tap(".panel-toggle")
  await german.select(".setting-select", "de")
  await wait(600)
  await german.waitForSelector(".prompt")
  check("with German chosen, Grammar is still there but off",
    await tabs(german),
    [ { tag: "SPAN", label: "Vocab", href: null, current: "page", disabled: null, on: true, off: false }
    , { tag: "BUTTON", label: "Grammar", href: null, current: null, disabled: "true", on: false, off: true }
    ])
  check("and nothing is said until it is tapped", await german.$(".notice"), null)
  const before = german.url()
  await german.click("button.tab")
  await wait(150)
  check("tapping it says why", await german.text(".notice"), "Grammar is only in Spanish for now")
  check("and goes nowhere", german.url(), before)
  check("the bar did not move", await placed(german), { onScreen: true, belowControls: true })
  await wait(3800)
  check("the notice goes by itself", await german.$(".notice"), null)

  // And choosing Spanish again gives the link back.
  await german.tap(".panel-toggle")
  await german.select(".setting-select", "es")
  await wait(600)
  check("Spanish brings Grammar back as a link",
    (await tabs(german)).map(t => [t.label, t.tag, t.off]), [["Vocab", "SPAN", false], ["Grammar", "A", false]])
  check("no page errors", german.errors, [])
  await german.close()
}
