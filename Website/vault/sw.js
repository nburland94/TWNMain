// Needed Vault keeps itself on the phone: after the first visit it opens with no signal.
// Only the page lives here — your photos stay in the phone's own storage, never on the website.
const CACHE = 'needed-vault-r21';
const SHELL = ['./', 'index.html', 'app.js', 'manifest.webmanifest', 'mark.png', 'icon-180.png', 'icon-192.png', 'icon-512.png',
  'fonts/raleway-latin-200-normal.woff2', 'fonts/raleway-latin-300-normal.woff2', 'fonts/raleway-latin-400-normal.woff2',
  'fonts/raleway-latin-500-normal.woff2', 'fonts/oswald-latin-400-normal.woff2',
  'fonts/courier-prime-latin-400-normal.woff2', 'fonts/courier-prime-latin-700-normal.woff2'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// The copy on the phone straight away; a fresh one fetched behind it for next time.
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(caches.open(CACHE).then(c => c.match(e.request, { ignoreSearch: true }).then(hit => {
    const net = fetch(e.request).then(r => { if (r && r.ok) c.put(e.request.url.split('?')[0], r.clone()); return r; }).catch(() => hit);
    return hit || net;
  })));
});
