/* Needed Tools — liquid glass, the same as the website's nav bar, on every page and tool.
   1. The glass itself: almost clear, blurred and saturated, a fine white edge, a bright line
      along the top and a soft sheen in the top centre — by day and by night.
   2. Every switch with a selected option (.seg, .seg2) gets a glass lens that slides to the
      option you pick: it stretches like a drop of water on the way, overshoots a touch and
      settles (~0.6s). Keyboard, clicks and code that sets .on all move it the same way.
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
  const SPRING = 'cubic-bezier(0.34, 1.45, 0.52, 1)';

  const css = `
${BARS}{background:${SHEEN},linear-gradient(180deg,rgba(255,255,255,0.30),rgba(255,255,255,0.10) 42%,rgba(255,255,255,0.08));
  border:1px solid rgba(255,255,255,0.42);-webkit-backdrop-filter:${FILTER};backdrop-filter:${FILTER};
  box-shadow:0 8px 32px rgba(0,0,0,0.08),0 2px 8px rgba(0,0,0,0.04),inset 0 1.5px 0 rgba(255,255,255,0.82),inset 0 -1px 0 rgba(0,0,0,0.03)}
${PANELS}{background:${SHEEN},linear-gradient(160deg,rgba(255,255,255,0.54),rgba(255,255,255,0.30) 55%,rgba(255,255,255,0.38));
  border:1px solid rgba(255,255,255,0.42);-webkit-backdrop-filter:${FILTER};backdrop-filter:${FILTER}}

/* the lens */
.nglass{position:relative;isolation:isolate}
.nglass>.nlens{position:absolute;left:0;top:0;width:0;height:0;z-index:0;box-sizing:border-box;border-radius:100px;pointer-events:none;opacity:0;
  background:${SHEEN},rgba(255,255,255,0.72);border:1px solid rgba(255,255,255,0.95);
  box-shadow:inset 0 1.5px 0 #fff,inset 0 -2px 6px rgba(0,0,0,0.05),0 3px 12px rgba(20,20,20,0.13),0 0 0 0.5px rgba(20,20,20,0.07);
  -webkit-backdrop-filter:blur(6px) saturate(160%) brightness(1.08);backdrop-filter:blur(6px) saturate(160%) brightness(1.08);
  transition:left .62s ${SPRING},top .62s ${SPRING},width .5s ${SPRING},height .5s ${SPRING},opacity .2s ease-out}
.nglass>.nlens.nsq1{animation:nsq1 .62s ease-out}
.nglass>.nlens.nsq2{animation:nsq2 .62s ease-out}
@keyframes nsq1{0%{transform:scale(1,1)}30%{transform:scale(1.22,0.86)}62%{transform:scale(0.95,1.05)}82%{transform:scale(1.02,0.99)}100%{transform:scale(1,1)}}
@keyframes nsq2{0%{transform:scale(1,1)}30%{transform:scale(1.22,0.86)}62%{transform:scale(0.95,1.05)}82%{transform:scale(1.02,0.99)}100%{transform:scale(1,1)}}
.nglass>button{position:relative;z-index:1}
.nglass.lensed>button.on{background:transparent!important;box-shadow:none!important;color:#141414!important}
@media (prefers-reduced-motion:reduce){.nglass>.nlens{transition:opacity .2s}.nglass>.nlens.nsq1,.nglass>.nlens.nsq2{animation:none}}

/* by night: the same glass, dark — never an opaque navy tile */
html[data-theme=dark] body ${BARS.split(', ').join(`,html[data-theme=dark] body `)}{
  background:${SHEEN_NIGHT},linear-gradient(180deg,rgba(40,58,86,0.46),rgba(22,34,52,0.30))!important;
  border-color:rgba(255,255,255,0.16)!important;
  box-shadow:0 10px 36px rgba(0,0,0,0.40),0 2px 8px rgba(0,0,0,0.22),inset 0 1.5px 0 rgba(255,255,255,0.20),inset 0 -1px 0 rgba(0,0,0,0.20)!important}
html[data-theme=dark] body ${PANELS.split(', ').join(`,html[data-theme=dark] body `)}{
  background:${SHEEN_NIGHT},linear-gradient(160deg,rgba(40,58,86,0.62),rgba(22,34,52,0.46) 55%,rgba(28,42,64,0.52))!important;
  border-color:rgba(255,255,255,0.14)!important}
html[data-theme=dark] body .nglass>.nlens{background:${SHEEN_NIGHT},rgba(255,255,255,0.15)!important;border-color:rgba(255,255,255,0.30)!important;
  box-shadow:inset 0 1.5px 0 rgba(255,255,255,0.38),inset 0 -2px 6px rgba(0,0,0,0.20),0 4px 14px rgba(0,0,0,0.38)!important}
html[data-theme=dark] body .nglass.lensed>button.on{color:#f4f7fb!important}
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
    const x = on.offsetLeft, y = on.offsetTop, w = on.offsetWidth, h = on.offsetHeight;
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
    // Radius follows the button, so a square switch gets a square lens.
    l.style.borderRadius = getComputedStyle(on).borderRadius || '100px';
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
