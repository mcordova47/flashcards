export const current = () =>
  typeof window === "undefined" ? "/" : window.location.pathname

export const replace_ = path => {
  if (typeof window === "undefined" || !window.history) return
  window.history.replaceState(null, "", path)
}
