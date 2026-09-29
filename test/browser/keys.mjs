import { speechStub, slugAt, wait } from "./harness.mjs"

export const name = "Keys with something over the page"

const done = page => page.$$eval(".pip.done", ps => ps.length)

const fromMenu = async (page, label) => {
  await page.tap(".panel-toggle")
  ;(await page.byText(".panel-item", label)).click()
  await wait(250)
}

export default async ({ check, open }) => {
  // --- the cards, with one answered and the next one up ---
  // Answered, so that `z` has something to take back if it gets through.
  const cards = await open({ stub: speechStub() })
  await cards.waitForSelector(".prompt")
  await wait(450)
  await cards.tap(".card")
  await cards.tap(".got-it")
  const prompt = await cards.text(".prompt")
  check("a second card is up", prompt, slugAt(2))
  const spoken = (await cards.spoken()).length

  // One key at a time, and the card read after each: pressed together, `2`
  // grades the card and `z` takes the grade straight back, and a page that
  // heard both would look like one that heard neither.
  const card = async () => [
    await cards.text(".prompt"), !!(await cards.$(".answer")), await done(cards),
    (await cards.spoken()).length,
  ]
  const eachKey = async (what, turned, keys) => {
    for (const key of keys) {
      await cards.keyboard.press(key)
      await wait(150)
      check(`${JSON.stringify(key)} ${what} leaves the card alone`, await card(), [prompt, turned, 1, spoken])
    }
  }

  const pairing = async () => {
    await fromMenu(cards, "Sync another device")
    await cards.tap(".pair-paste")
  }
  const progress = () => fromMenu(cards, "See your progress")
  // The menu has a backdrop over the card, and the button last tapped keeps
  // focus, which is where an Enter lands.
  const menu = () => cards.tap(".panel-toggle")
  const close = () => cards.tap(".sheet-close")

  // Twice over, because the keys act on different cards: space and Enter turn
  // one that is face down and do nothing to one already turned, and the
  // grades are the other way round.
  //
  // In the pairing link, as a hand-typed one would arrive: a pairing key is
  // 32 of `[a-z0-9]`, so it is likely to hold a `1`, a `2` or a `z`. Enter is
  // where a reader would expect the link to be used, and the arrows move the
  // caret.
  await pairing()
  await eachKey("in the pairing link", false, ["a", " ", "b", "Enter"])
  check("a space can be typed into the link", await cards.$eval(".pair-paste", e => e.value), "a b")
  await close()
  // Nothing is typed on the progress sheet, but it covers the card all the
  // same.
  await progress()
  await eachKey("under the progress sheet", false, [" ", "Enter", "z"])
  await close()
  await menu()
  await eachKey("under the menu", false, [" ", "Enter", "z"])
  await cards.dismiss()
  check("still face down with every sheet closed", await card(), [prompt, false, 1, spoken])

  await cards.tap(".card")
  const turnedKeys = ["z", "1", "2", "s", "ArrowLeft", "ArrowRight"]
  await pairing()
  await eachKey("in the pairing link", true, turnedKeys)
  check("and every one of them is in it", await cards.$eval(".pair-paste", e => e.value), "z12s")
  await close()
  await progress()
  await eachKey("under the progress sheet", true, turnedKeys)
  await close()
  await menu()
  await eachKey("under the menu", true, turnedKeys)
  await cards.dismiss()
  check("still turned with every sheet closed", await card(), [prompt, true, 1, spoken])
  check("and the answer before it is still saved", (await cards.stored()).cards.length, 1)

  // Without which every check above would pass for a page that heard no keys
  // at all.
  await cards.keyboard.press("2")
  await wait(150)
  check("with nothing over it, the keys are the card's again", await done(cards), 2)
  check("no page errors", cards.errors, [])
  await cards.close()

  // --- the drills, with an answer typed and not yet checked ---
  // Enter is the one key the drills map, and with a sheet over the question it
  // would check the answer behind it.
  const drills = await open({ path: "/verbs", key: "flashcards.verbs.v1" })
  await drills.waitForSelector(".verb-sentence")
  await wait(400)
  await drills.type(".verb-answer", "nada")

  await drills.tap(".panel-toggle")
  await drills.keyboard.press("Enter")
  await drills.dismiss()
  check("the menu does not let Enter check the answer",
    [await drills.text(".milestone"), await done(drills)], [null, 0])
  await fromMenu(drills, "See your progress")
  await drills.keyboard.press("Enter")
  await drills.tap(".sheet-close")
  check("nor does the progress sheet", [await drills.text(".milestone"), await done(drills)], [null, 0])

  await drills.keyboard.press("Enter")
  await wait(150)
  check("with nothing over it, Enter checks it", await done(drills), 1)
  check("no page errors", drills.errors, [])
  await drills.close()
}
