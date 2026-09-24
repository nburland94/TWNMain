/* Needed Tools — dark mode: a calm blue night, across every page.
   Rather than a second copy of every page's colours, the colours on screen are
   turned into their night versions as they appear: light surfaces become deep
   navy, dark words become light, the apricot glow becomes a blue one, and the
   orange accents a soft blue. Your pictures, colour swatches and Design pages
   keep their true colours. Switching back puts every colour back exactly. */
(function () {
  if (window.__neededTheme) return;
  const DARK = 'dark';
  // What keeps its true colours: designs, pictures, palettes and swatches.
  const KEEP = 'video, canvas, .pg, .gart, #render, .sw, .swatch, .swatches, .colours, .pal, .palette, .strip .thumb, [data-true-colour], #play, .moodpage, .mpage';
  const PROPS = ['color', 'background-color', 'background-image', 'background', 'border-color', 'border-top-color', 'border-right-color', 'border-bottom-color',
    'border-left-color', 'outline-color', 'box-shadow', 'text-shadow', 'fill', 'stroke', 'caret-color', 'text-decoration-color', 'accent-color', 'border'];
  const COLOUR = /#([0-9a-f]{8}|[0-9a-f]{6}|[0-9a-f]{3,4})\b|rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.]+%?))?\s*\)|\b(white|black)\b/gi;

  const lerp = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
  function parse(m) {
    if (m[6]) return m[6].toLowerCase() === 'white' ? [255, 255, 255, 1] : [0, 0, 0, 1];
    if (m[1]) {
      let h = m[1];
      if (h.length <= 4) h = h.split('').map(c => c + c).join('');
      const n = parseInt(h.slice(0, 6), 16);
      return [(n >> 16) & 255, (n >> 8) & 255, n & 255, h.length === 8 ? parseInt(h.slice(6), 16) / 255 : 1];
    }
    const a = m[5] == null ? 1 : /%$/.test(m[5]) ? parseFloat(m[5]) / 100 : +m[5];
    return [+m[2], +m[3], +m[4], a];
  }
  const out = ([r, g, b, a]) => a >= 1 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${+a.toFixed(3)})`;

  // One colour, by night.
  function night(c, shadow) {
    const [r, g, b, a] = c;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), s = mx ? (mx - mn) / mx : 0;
    const L = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    if (shadow) return L > 0.7 ? [255, 255, 255, a * 0.07] : [0, 0, 0, Math.min(0.55, a * 2.2)];
    let hue = 0;
    if (mx !== mn) { const d = mx - mn; hue = mx === r ? 60 * (((g - b) / d) % 6) : mx === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4); if (hue < 0) hue += 360; }
    const warm = hue >= 4 && hue <= 42;
    // The glow and pale tints: the lightest become the deepest navy, the warmest a blue light.
    if (L > 0.7 && s > 0.1 && warm) return [...lerp([46, 86, 132], [13, 22, 35], Math.min(1, (L - 0.7) / 0.28)), a];
    // The accents: orange becomes a calm blue — lighter where it's words, fuller where it's a button.
    if (warm && s >= 0.6) return [...(L < 0.45 ? [140, 190, 255] : [74, 140, 232]), a];
    // Neutrals: light becomes night, dark becomes light.
    if (s < 0.6 || L > 0.85) { const t = Math.pow(1 - L, 1.05); return [...lerp([13, 21, 33], [234, 240, 247], t), a]; }
    // Every other colour (a red number, a green "paid"): the same, a little lighter.
    return [...lerp([r, g, b], [255, 255, 255], 0.22), a];
  }
  const convert = (value, shadow) => String(value).replace(COLOUR, (...m) => out(night(parse(m), shadow)));

  /* ---------------------------------------------------------------- the stylesheets */
  let night_ = null;
  const done = new WeakSet();
  function rulesFrom(list, wrap) {
    const lines = [];
    for (const rule of list) {
      if (rule.cssRules && rule.media) { const inner = rulesFrom(rule.cssRules); if (inner.length) lines.push(`@media ${rule.media.mediaText}{${inner.join('')}}`); continue; }
      if (!rule.style || !rule.selectorText) continue;
      // Designs, swatches — and film players, which stay black.
      if (/\.pg\b|#render|\.swatch|\.sw\b|\.pal\b|\.colours|\.palette|\bvideo\b|\bcanvas\b|\bimg\b|\.itemmedia|\.film\b|\.pvstage/.test(rule.selectorText)) continue;
      const decl = [];
      for (let i = 0; i < rule.style.length; i++) {
        const p = rule.style[i];
        if (!PROPS.includes(p) && !/-color$/.test(p) && !/^background/.test(p) && !p.startsWith('--')) continue;
        const v = rule.style.getPropertyValue(p);
        if (!v || !COLOUR.test(v)) { COLOUR.lastIndex = 0; continue; }
        COLOUR.lastIndex = 0;
        decl.push(`${p}:${convert(v, /shadow/.test(p))}${rule.style.getPropertyPriority(p) ? ' !important' : ''}`);
      }
      if (decl.length) lines.push(rule.selectorText.split(',').map(s => /^\s*(html|:root)\b/.test(s) ? s.replace(/^\s*(html|:root)/, 'html[data-theme=dark]') : `html[data-theme=dark] ${s.trim()}`).join(',') + `{${decl.join(';')}}`);
    }
    return lines;
  }
  function sheets() {
    if (!night_) { night_ = document.createElement('style'); night_.id = 'neededNight'; }
    let add = '';
    for (const sh of Array.from(document.styleSheets)) {
      if (sh.ownerNode === night_ || done.has(sh)) continue;
      let rules; try { rules = sh.cssRules; } catch (e) { continue; }
      done.add(sh);
      add += rulesFrom(rules).join('\n') + '\n';
    }
    // The bits no stylesheet can know about (once).
    if (!night_.dataset.base) { night_.dataset.base = '1'; add += `html[data-theme=dark]{color-scheme:dark}
      html[data-theme=dark] body{background-color:#0d1521}
      html[data-theme=dark] img[src$="mark.png"]:not(.pg *),html[data-theme=dark] img[src*="/_blob/"]:not(.pg *),html[data-theme=dark] .brand img,html[data-theme=dark] .markrow img{filter:brightness(0) invert(1)}
      html[data-theme=dark] ::selection{background:rgba(74,140,232,0.35)}
      html[data-theme=dark] input,html[data-theme=dark] textarea,html[data-theme=dark] select{color:#eaf0f7}
      html[data-theme=dark] ::placeholder{color:rgba(234,240,247,0.38)}`; }
    night_.textContent += add;
    if (!night_.isConnected) (document.head || document.documentElement).appendChild(night_);
  }

  /* ---------------------------------------------------------------- colours set on the page itself */
  const orig = new WeakMap();                 // element → its own colours, to put back
  const keep = el => el.closest && el.closest(KEEP);
  function paint(el) {
    if (!(el instanceof Element) || keep(el)) return;
    const st = el.getAttribute('style');
    if (st && COLOUR.test(st)) {
      COLOUR.lastIndex = 0;
      const o = orig.get(el) || {};
      if (o.painted !== st) {
        o.style = st;
        const next = st.replace(/([a-z-]+)\s*:\s*([^;]+)/gi, (all, p, v) => (PROPS.includes(p.toLowerCase()) || /-color$/i.test(p) || /^background/i.test(p)) ? `${p}:${convert(v, /shadow/i.test(p))}` : all);
        o.painted = next; orig.set(el, o);
        if (next !== st) el.setAttribute('style', next);
      }
    } else COLOUR.lastIndex = 0;
    for (const a of ['fill', 'stroke']) {
      const v = el.getAttribute(a);
      if (v && v !== 'none' && COLOUR.test(v)) {
        COLOUR.lastIndex = 0;
        const o = orig.get(el) || {};
        if (o[a + 'P'] !== v) { o[a] = v; o[a + 'P'] = convert(v); orig.set(el, o); el.setAttribute(a, o[a + 'P']); }
      } else COLOUR.lastIndex = 0;
    }
  }
  function paintAll(root) {
    if (root instanceof Element) paint(root);
    (root.querySelectorAll ? root.querySelectorAll('[style],[fill],[stroke]') : []).forEach(paint);
  }
  function unpaintAll() {
    document.querySelectorAll('[style],[fill],[stroke]').forEach(el => {
      const o = orig.get(el); if (!o) return;
      if (o.style != null && el.getAttribute('style') === o.painted) el.setAttribute('style', o.style);
      for (const a of ['fill', 'stroke']) if (o[a] != null && el.getAttribute(a) === o[a + 'P']) el.setAttribute(a, o[a]);
      orig.delete(el);
    });
  }
  let watching = null;
  function watch() {
    if (watching) return;
    watching = new MutationObserver(list => {
      let styles = false;
      for (const m of list) {
        if (m.type === 'attributes') { const o = orig.get(m.target); if (!o || m.target.getAttribute(m.attributeName) !== (m.attributeName === 'style' ? o.painted : o[m.attributeName + 'P'])) paint(m.target); }
        else m.addedNodes.forEach(n => { if (n.nodeName === 'STYLE' || n.nodeName === 'LINK') styles = true; else if (n.nodeType === 1) paintAll(n); });
      }
      if (styles) setTimeout(sheets, 0);
    });
    watching.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['style', 'fill', 'stroke'] });
  }

  /* ---------------------------------------------------------------- switching */
  function apply(t) {
    const dark = t === DARK;
    if (dark) {
      sheets(); paintAll(document.documentElement); watch();
      document.documentElement.setAttribute('data-theme', DARK);
      document.querySelectorAll('link[rel=stylesheet]').forEach(l => l.addEventListener('load', sheets, { once: true }));
    } else {
      if (watching) { watching.disconnect(); watching = null; }
      document.documentElement.removeAttribute('data-theme');
      unpaintAll();
    }
  }
  window.__neededTheme = apply;
  const start = () => apply(window.__neededThemeNow || 'light');
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  window.addEventListener('load', () => { if (document.documentElement.getAttribute('data-theme') === DARK) sheets(); });
})();
