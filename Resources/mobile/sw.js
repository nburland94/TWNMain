// Needed Vault opens offline: the page and its fonts are kept on the phone.
const CACHE = 'needed-vault-2';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'mark.png', 'icon-180.png', 'icon-192.png', 'icon-512.png',
  'fonts/raleway-latin-200-normal.woff2', 'fonts/raleway-latin-300-normal.woff2', 'fonts/raleway-latin-400-normal.woff2', 'fonts/raleway-latin-500-normal.woff2',
  'fonts/oswald-latin-400-normal.woff2', 'fonts/courier-prime-latin-400-normal.woff2', 'fonts/courier-prime-latin-700-normal.woff2'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // The page itself: fresh when online, kept copy when not. Everything else: kept copy first.
  if (e.request.mode === 'navigate') {
    e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(CACHE).then(k => k.put('index.html', c)); return r; }).catch(() => caches.match('index.html')));
    return;
  }
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
