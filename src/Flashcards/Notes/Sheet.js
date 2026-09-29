// The draft is read when it is saved rather than tracked keystroke by
// keystroke, for the reason `Sync.pastedLink` gives: a controlled field fed by
// an update loop that dispatches asynchronously loses the caret between
// renders, and a note is typed at speed on a phone.
export const draft = () => {
  const field = document.querySelector(".note-draft")
  return field ? field.value : ""
}

export const clearDraft = () => {
  const field = document.querySelector(".note-draft")
  if (field) field.value = ""
}

// As `Sync.copyLink`, and for the same reason reports rather than assumes: the
// clipboard needs a user activation that can be lost on the way through the
// update loop, and "copied" said of something that was not is worse than
// saying nothing.
export const copy_ = (text, done) => {
  if (!navigator.clipboard) return done(false)
  navigator.clipboard.writeText(text).then(() => done(true)).catch(() => done(false))
}
