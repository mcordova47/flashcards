export const onKeyDown_ = handler => {
  window.addEventListener("keydown", e => {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    // A textarea is somewhere to write, so its keys are its own: a space is a
    // space and Enter a new line, where the page would flip or answer or undo
    // whatever is behind it. Before the space is stopped, which would
    // otherwise make one impossible to type.
    if (e.target instanceof HTMLTextAreaElement) return
    // Otherwise the flip key scrolls the page. Not from a text box, though,
    // where stopping it means no space can be typed. The page still hears it,
    // as it hears Enter from the drills' answer box, which relies on that - so
    // a page with a text box on a sheet ignores keys while the sheet is open.
    if (e.key === " " && !(e.target instanceof HTMLInputElement)) e.preventDefault()
    // A focused button treats Enter and Space as a click, so whichever button
    // was last tapped would fire again alongside whatever the page maps the
    // key to - answering a question nobody read. Both pages map both keys, so
    // the page's meaning is the one to keep: it knows what the key means,
    // where the button only knows it was pressed.
    if (e.target instanceof HTMLButtonElement && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault()
    }
    handler(e.key)
  })
}
