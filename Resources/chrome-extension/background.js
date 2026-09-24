// Needed Vault — right-click any image → Save to Needed Vault.
// Talks only to the Needed Vault app on this Mac (127.0.0.1).

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'needed-vault', title: 'Save to Needed Vault', contexts: ['image'] });
});

function flash(tabId, text, colour) {
  chrome.action.setBadgeBackgroundColor({ color: colour, tabId });
  chrome.action.setBadgeText({ text, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: '', tabId }), 2500);
}

// The biggest version the page offers — its srcset and <picture> sources —
// not just the one on screen.
async function biggest(tabId, src) {
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId }, args: [src],
      func: src => {
        const img = [...document.images].find(i => i.currentSrc === src || i.src === src);
        if (!img) return { url: src, html: '' };
        const sets = [img.getAttribute('srcset') || ''];
        const pic = img.closest('picture');
        if (pic) pic.querySelectorAll('source').forEach(s => sets.push(s.getAttribute('srcset') || ''));
        let best = { url: img.currentSrc || src, size: img.naturalWidth || 0 };
        for (const set of sets) for (const part of set.split(',')) {
          const [u, d] = part.trim().split(/\s+/);
          if (!u) continue;
          const n = !d ? 0 : d.endsWith('x') ? parseFloat(d) * (img.naturalWidth || 1000) : parseFloat(d);
          if (n > best.size) best = { url: new URL(u, location.href).href, size: n };
        }
        return { url: best.url, html: img.outerHTML };
      },
    });
    return (r && r.result) || { url: src, html: '' };
  } catch (e) {
    return { url: src, html: '' };
  }
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== 'needed-vault' || !info.srcUrl) return;
  const found = await biggest(tab.id, info.srcUrl);
  try {
    const res = await fetch('http://127.0.0.1:47631/grab', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Needed-Vault': '1' },
      body: JSON.stringify({ img: found.url, html: found.html, page: tab.url, title: tab.title }),
    });
    const j = await res.json().catch(() => ({}));
    flash(tab.id, j.ok ? '✓' : '!', j.ok ? '#3a9d5a' : '#c9472a');
  } catch (e) {
    flash(tab.id, 'off', '#c9472a');          // Needed Vault isn't open
  }
});
