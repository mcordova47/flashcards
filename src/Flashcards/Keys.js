export const onKeyDown_ = handler => {
  window.addEventListener("keydown", e => {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    // Otherwise the flip key scrolls the page.
    if (e.key === " ") e.preventDefault()
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
