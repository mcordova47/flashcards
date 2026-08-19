// Network-first, cache as fallback.
//
// The app is 76 KB, so caching buys almost nothing in speed but everything in
// being usable underground. Network-first means a deploy always wins and you
// can never get wedged on a stale bundle — the failure mode that makes
// cache-first service workers miserable to debug.

const CACHE = "mil-palabras-__VERSION__"

const SHELL = [
  "/",
  "/index.js",
  "/assets/stylesheets/theme.css",
  "/assets/manifest.webmanifest",
  "/assets/images/favicon.svg",
  "/assets/images/icon-192.png",
  "/assets/images/icon-512.png",
  "/assets/images/apple-touch-icon.png",
]

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", event => {
  const { request } = event
  if (request.method !== "GET") return
  if (new URL(request.url).origin !== self.location.origin) return

  event.respondWith(
    fetch(request)
      .then(response => {
        // Keep the cache warm for the next time there is no signal.
        if (response.ok) {
          const copy = response.clone()
          caches.open(CACHE).then(cache => cache.put(request, copy))
        }
        return response
      })
      .catch(() =>
        caches.match(request).then(hit =>
          // A navigation to any path resolves to the one entry point.
          hit ?? (request.mode === "navigate" ? caches.match("/") : undefined)
        )
      )
  )
})
