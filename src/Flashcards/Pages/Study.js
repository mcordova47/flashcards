export const onKeyDown_ = handler => {
  window.addEventListener("keydown", e => {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    // Otherwise the flip key scrolls the page.
    if (e.key === " ") e.preventDefault()
    handler(e.key)
  })
}
