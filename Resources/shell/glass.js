/* Needed Tools — liquid glass, the same as the website's nav bar, on every page and tool.
   1. The glass itself: almost clear, blurred and saturated, a fine white edge, a bright line
      along the top and a soft sheen in the top centre — by day and by night.
   2. Every switch with a selected option (.seg, .seg2) gets an orange lens (white words on it) that
      slides to the option you pick: it stretches like a drop of water on the way and lands inside
      the pill (~0.55s), in light and dark. Keyboard, clicks and code that sets .on all move it the same way.
   Loaded with theme.js (Shell.swift), before it, so dark mode sees these rules too. */
(function () {
  if (window.__neededGlass) return;
  window.__neededGlass = true;

  const SHEEN = 'radial-gradient(ellipse 55% 30% at 50% 0%, rgba(255,255,255,0.62) 0%, rgba(255,255,255,0) 100%)';
  const SHEEN_NIGHT = 'radial-gradient(ellipse 55% 30% at 50% 0%, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0) 100%)';
  const FILTER = 'blur(40px) saturate(240%) brightness(1.04)';
  // Floating bars and pills: the website's recipe exactly.
  const BARS = '.toast, .needed-load, .qbar';
  // Panels and notes hold reading text, so they keep a little more white behind the words.
  const PANELS = '.g, .nt-tip, .qtip';
  // A glide that lands exactly (no overshoot past the pill); the stretch happens mid-way.
  const GLIDE = 'cubic-bezier(0.22, 1, 0.36, 1)';

  const css = `
${BARS}{background:${SHEEN},linear-gradient(180deg,rgba(255,255,255,0.30),rgba(255,255,255,0.10) 42%,rgba(255,255,255,0.08));
  border:1px solid rgba(255,255,255,0.42);-webkit-backdrop-filter:${FILTER};backdrop-filter:${FILTER};
  box-shadow:0 8px 32px rgba(0,0,0,0.08),0 2px 8px rgba(0,0,0,0.04),inset 0 1.5px 0 rgba(255,255,255,0.82),inset 0 -1px 0 rgba(0,0,0,0.03)}
${PANELS}{background:${SHEEN},linear-gradient(160deg,rgba(255,255,255,0.54),rgba(255,255,255,0.30) 55%,rgba(255,255,255,0.38));
  border:1px solid rgba(255,255,255,0.42);-webkit-backdrop-filter:${FILTER};backdrop-filter:${FILTER}}

/* the lens: solid orange, inside its pill with an even gap, no outline of its own */
.nglass{position:relative;isolation:isolate;overflow:hidden}
.nglass>.nlens{position:absolute;left:0;top:0;width:0;height:0;z-index:0;box-sizing:border-box;border-radius:999px;pointer-events:none;opacity:0;
  background:linear-gradient(180deg,#f46a33,#F05A22);border:none;box-shadow:inset 0 1px 0 rgba(255,255,255,0.28),0 1px 3px rgba(160,50,10,0.22);
  transition:left .55s ${GLIDE},top .55s ${GLIDE},width .45s ${GLIDE},height .45s ${GLIDE},opacity .2s ease-out}
.nglass>.nlens.nsq1{animation:nsq1 .55s ease-out}
.nglass>.nlens.nsq2{animation:nsq2 .55s ease-out}
@keyframes nsq1{0%{transform:scale(1,1)}35%{transform:scale(1.16,0.9)}70%{transform:scale(0.98,1.02)}100%{transform:scale(1,1)}}
@keyframes nsq2{0%{transform:scale(1,1)}35%{transform:scale(1.16,0.9)}70%{transform:scale(0.98,1.02)}100%{transform:scale(1,1)}}
.nglass>button{position:relative;z-index:1}
.nglass.lensed>button.on{background:transparent!important;box-shadow:none!important;color:#ffffff!important;border-color:transparent!important}
@media (prefers-reduced-motion:reduce){.nglass>.nlens{transition:opacity .2s}.nglass>.nlens.nsq1,.nglass>.nlens.nsq2{animation:none}}

/* by night: the same glass, dark — never an opaque navy tile */
html[data-theme=dark] body ${BARS.split(', ').join(`,html[data-theme=dark] body `)}{
  background:${SHEEN_NIGHT},linear-gradient(180deg,rgba(40,58,86,0.46),rgba(22,34,52,0.30))!important;
  border-color:rgba(255,255,255,0.16)!important;
  box-shadow:0 10px 36px rgba(0,0,0,0.40),0 2px 8px rgba(0,0,0,0.22),inset 0 1.5px 0 rgba(255,255,255,0.20),inset 0 -1px 0 rgba(0,0,0,0.20)!important}
html[data-theme=dark] body ${PANELS.split(', ').join(`,html[data-theme=dark] body `)}{
  background:${SHEEN_NIGHT},linear-gradient(160deg,rgba(40,58,86,0.62),rgba(22,34,52,0.46) 55%,rgba(28,42,64,0.52))!important;
  border-color:rgba(255,255,255,0.14)!important}
html[data-theme=dark] body .nglass>.nlens{background:linear-gradient(180deg,#f46a33,#F05A22)!important;border:none!important;box-shadow:inset 0 1px 0 rgba(255,255,255,0.22),0 1px 4px rgba(0,0,0,0.35)!important}
html[data-theme=dark] body .nglass.lensed>button.on{color:#ffffff!important}
`;
  const style = document.createElement('style');
  style.id = 'neededGlass';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  /* ---------------------------------------------------------------- the sliding lens */
  const SEGS = '.seg, .seg2';
  const last = new Map();
  function lensOf(seg) {
    let l = seg.querySelector(':scope > .nlens');
    if (!l) {
      l = document.createElement('i');
      l.className = 'nlens';
      l.setAttribute('aria-hidden', 'true');
      seg.classList.add('nglass');
      seg.insertBefore(l, seg.firstChild);
    }
    return l;
  }
  function place(seg, animate) {
    const l = lensOf(seg);
    // Only a selected button gets the lens; a selected dropdown keeps its own look.
    const on = seg.querySelector(':scope > button.on');
    if (!on || !on.offsetWidth) { l.style.opacity = '0'; seg.classList.remove('lensed'); l._x = null; return; }
    // An even gap all round, so the lens sits inside the pill instead of on its edge.
    const gap = 2, x = on.offsetLeft + gap, y = on.offsetTop + gap, w = Math.max(0, on.offsetWidth - 2 * gap), h = Math.max(0, on.offsetHeight - 2 * gap);
    if (l._x === x && l._y === y && l._w === w && l._h === h) return;
    // A page that redraws its switch (Design does, on every click) keeps the lens's last place, so it still slides.
    const words = s => [...s.children].filter(b => b.tagName === 'BUTTON').map(b => b.textContent.trim()).join('|');
    const own = words(seg), twins = [...document.querySelectorAll(SEGS)].filter(s => words(s) === own);
    const sig = own + '#' + twins.indexOf(seg);
    if (l._x == null && animate !== false && last.has(sig)) {
      const p = last.get(sig);
      if (p.x !== x || p.y !== y) {
        l.style.transition = 'none';
        Object.assign(l.style, { left: p.x + 'px', top: p.y + 'px', width: p.w + 'px', height: p.h + 'px', opacity: '1' });
        void l.offsetWidth;
        l.style.transition = '';
        l._x = p.x; l._y = p.y; l._w = p.w; l._h = p.h;
        animate = true;
      }
    }
    last.set(sig, { x, y, w, h });
    const moved = l._x != null && Math.abs(l._x - x) > 2;
    if (!animate || l._x == null) {
      l.style.transition = 'none';
      Object.assign(l.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px', opacity: '1' });
      void l.offsetWidth;
      l.style.transition = '';
    } else {
      Object.assign(l.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px', opacity: '1' });
      if (moved) { l.classList.remove('nsq1', 'nsq2'); l.classList.add(l._f ? 'nsq1' : 'nsq2'); l._f = !l._f; }
    }
    seg.classList.add('lensed');
    l._x = x; l._y = y; l._w = w; l._h = h;
  }
  const seen = new WeakSet();
  function adopt(root) {
    const list = [];
    if (root.matches && root.matches(SEGS)) list.push(root);
    if (root.querySelectorAll) root.querySelectorAll(SEGS).forEach(s => list.push(s));
    list.forEach(seg => { const first = !seen.has(seg); seen.add(seg); place(seg, first ? 'new' : true); });
  }
  let queued = new Set(), frame = 0;
  function later(seg) {
    queued.add(seg);
    if (!frame) frame = requestAnimationFrame(() => { frame = 0; const q = queued; queued = new Set(); q.forEach(s => { if (s.isConnected) place(s, true); }); });
  }
  function start() {
    adopt(document);
    new MutationObserver(list => {
      for (const m of list) {
        if (m.type === 'attributes') {
          const seg = m.target.parentElement;
          if (seg && seg.matches && seg.matches(SEGS)) later(seg);
        } else m.addedNodes.forEach(n => {
          if (n.nodeType !== 1 || n.classList.contains('nlens')) return;
          if (n.parentElement && n.parentElement.matches(SEGS)) later(n.parentElement);
          adopt(n);
        });
      }
    }).observe(document.body || document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class'] });
    // A panel that opens, a window that resizes or fonts that arrive can move the options under a lens.
    const again = () => document.querySelectorAll('.nglass').forEach(s => place(s, false));
    window.addEventListener('resize', again);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(again);
    setInterval(() => document.querySelectorAll('.nglass').forEach(s => { if (s.querySelector(':scope > .nlens')?.style.opacity === '0') place(s, false); }), 1200);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
