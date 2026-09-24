/* Needed Tools — the walkthrough inside each tool.
   Small liquid-glass notes beside the real controls, one at a time, with a
   soft ring round what to click. Steps whose control isn't on screen yet
   (Grab's "Grab this frame" before a film is in) wait and appear when it is.
   Every step is shown, in order; one whose control isn't on screen yet points
   to where it will appear. It runs each time you open the tool — ✕ closes it
   for this visit — until "Don't show again". ? replays it. */
(function () {
  if (window.__neededHints) return;
  // [control, title, note, where to point if the control isn't on screen yet, when it appears]
  const TOURS = {
    'neededvault:': [
      ['#linkInput', 'Paste a link', 'YouTube, Vimeo or Instagram. It plays right here, ready to grab from.'],
      ['#addToVault', 'Add to vault', 'Choose images, GIFs or clips from Finder — or drag them onto this window. They go into this project\u2019s references.'],
      ['#grabGoBtn', 'Grab & Go', 'Switch it on, then right-click any image in your browser and choose Copy Image. It saves straight into your project.'],
      ["#views button[data-view='vault']", 'Your vault', 'Everything you\u2019ve kept, by project. Tag it, put it on boards, find it by colour.'],
      ['#grabBtn', 'Grab a still', 'Pause where you like and press this, or G. The arrow keys step a frame at a time.', '#linkInput', 'Once a link or film is playing'],
      ['#inBtn2', 'Mark a GIF or MP4', 'Press I at the start and O at the end — up to ten seconds.', '#linkInput', 'Once a link or film is playing'],
      ['#tray .shapes', 'Each still\u2019s shapes', 'Under every still: Original, 16:9, 4:5, 1:1, 9:16. Pick which it saves as, then Frame these shapes to choose what\u2019s in shot. New stills start with the row below them.', '#linkInput', 'Once you\u2019ve grabbed a still'],
      ['#gifShapes', 'Shapes for the GIF and MP4', 'The GIF and the MP4 each have their own. Pick as many as you like \u2014 each shape saves as its own file.', '#linkInput', 'Once a link or film is playing'],
      ['#exportBtn', 'Save', 'Your stills go into the vault, filed under this project\u2019s Vault folder.'],
      ["#views button[data-design]", 'Mood boards', 'Now in Needed Design \u2014 or pick stills and press Make mood board, and they open there already placed.'],
    ],
    'neededshots:': [
      ['#beatsPanel', 'Paste your beats', 'A treatment or beat sheet — each line becomes a shot. Paste more later and only the new ones come in.'],
      ['#modeSeg', 'Shot list or Scene breakdown', 'Scene breakdown is one free line per beat, no dropdowns. Your shot details stay underneath.'],
      ['.refcell .add', 'Add references', 'Pulls stills from this project in your vault.'],
      ["#tabs button[data-tab='preview']", 'Preview', 'Check the page, the layout and the size before you export.'],
      ['#exportBtn', 'Export the PDF', 'It files into this project\u2019s Shots folder.'],
    ],
    'neededsort:': [
      ['#addCard', 'Add a card', 'Camera cards and the sound recorder, together. Add as many as the day had.'],
      ['#scanBtn', 'Scan', 'It reads when every clip was recorded and groups them into scenes.'],
      ['#gap', 'Scene breaks', 'How long a pause starts a new scene. Too many scenes? Drag it to the right.', '#scanBtn', 'After you scan'],
      ['.scene [data-open]', 'Open a scene', 'See every clip in it. Drag clips between scenes, and click a scene\u2019s name to rename its folder.', '#scanBtn', 'After you scan'],
      ['#destBtn', 'Where it goes', 'Choose where the project folder is made, in your folder structure.', '#scanBtn', 'After you scan'],
      ['#goBtn', 'Sort and copy', 'Every file is copied, then checked against the card before it says done.'],
    ],
    'neededgrab:': [
      ['#drop', 'Drop in a film', 'A finished film — drop it here, or choose it.'],
      ['#grabBtn', 'Grab a still', 'Pause where you like and press this, or G. The arrow keys step a frame at a time.', '#drop', 'Once a film is in'],
      ['#inBtn2', 'Mark a GIF or MP4', 'Press I at the start and O at the end — up to ten seconds.', '#drop', 'Once a film is in'],
      ['#tray .shapes', 'Each still\u2019s shapes', 'Under every still: Original, 16:9, 4:5, 1:1, 9:16. Pick which it saves as, then Frame these shapes to choose what\u2019s in shot. New stills start with the row below them.', '#drop', 'Once you\u2019ve grabbed a still'],
      ['#gifShapes', 'Shapes for the GIF and MP4', 'The GIF and the MP4 each have their own. Pick as many as you like \u2014 each shape saves as its own file.', '#drop', 'Once a film is in'],
      ['#exportBtn', 'Save', 'Everything files into this project\u2019s Grab folder.'],
    ],
    'neededcredit:': [
      ['#drop', 'The call sheet goes here', 'Drop the PDF here, or choose it — or paste the crew list into the box just below.'],
      ['#readBtn', 'Read it', 'Names and roles are pulled out and grouped by department.'],
      ['details.cache > summary', 'Crew memory', 'Handles you\u2019ve saved fill themselves in next time. You can add contacts in a batch here too.'],
      ['#copyBtn', 'Copy', 'The credit list, ready to paste into your post.'],
    ],
    'neededpay:': [
      ["#tabs button[data-tab='settings']", 'Start in Settings', 'Your details, tax numbers and bank — and your email, so invoices can send from here.'],
      ['#newInvoiceBtn', 'Make an invoice', 'Pick the client, add the work, add tax.'],
      ['#sendBtn', 'Send it', 'Straight to the client from your own email, PDF attached, with a copy to you.', '#newInvoiceBtn', 'On an invoice'],
      ["#tabs button[data-tab='dash']", 'Paid or not', 'Everything you\u2019re owed. Flip an invoice to paid when the money lands.'],
    ],
  };
  const steps = TOURS[location.protocol];
  if (!steps) return;
  const KEY = 'needed.tour';
  const load = () => { try { return JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { return {}; } };
  const store = s => { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { /* fine */ } };
  let state = load();                               // { off: true } once "Don't show again"
  state.done = [];                                  // each time a tool opens, the walkthrough starts from the top
  let dismissed = false;                            // ✕: gone for now, back next time

  const css = document.createElement('style');
  css.textContent = `
    .nt-tip{position:fixed;z-index:95;width:300px;border-radius:18px;padding:16px 18px 14px;font:13.5px/1.5 Raleway,sans-serif;color:#141414;
      background:linear-gradient(160deg,rgba(255,255,255,0.86),rgba(255,255,255,0.62));border:1px solid rgba(255,255,255,0.95);
      outline:0.5px solid rgba(120,55,20,0.14);outline-offset:-0.5px;
      box-shadow:inset 0 1.5px 0 #fff,0 22px 60px rgba(160,70,20,0.2),0 2px 8px rgba(160,70,20,0.06);
      -webkit-backdrop-filter:blur(26px) saturate(1.6);backdrop-filter:blur(26px) saturate(1.6);
      opacity:0;transform:translateY(6px) scale(0.98);transition:opacity .28s cubic-bezier(0.23,1,0.32,1),transform .28s cubic-bezier(0.23,1,0.32,1)}
    .nt-tip.on{opacity:1;transform:none}
    .nt-tip b{display:block;font-weight:400;font-size:17px;margin-bottom:4px;padding-right:20px}
    .nt-tip p{margin:0;color:#5a4a42}
    .nt-tip .x{position:absolute;right:10px;top:8px;border:none;background:none;font-size:16px;color:#8a7a72;cursor:pointer}
    .nt-tip .foot{display:flex;align-items:center;gap:8px;margin-top:12px}
    .nt-tip .n{font-size:11.5px;color:#8a7a72;margin-right:auto}
    .nt-tip button.b{border:none;border-radius:100px;padding:7px 14px;font:12.5px Raleway,sans-serif;cursor:pointer;background:rgba(255,255,255,0.7);color:#141414}
    .nt-tip button.go{background:linear-gradient(180deg,#2b2b2b,#111);color:#fff;box-shadow:inset 0 1px 0 rgba(255,255,255,0.14)}
    .nt-tip label{display:flex;align-items:center;gap:6px;margin-top:10px;font-size:12px;color:#7a6a62;cursor:pointer}
    .nt-tip label input{accent-color:#F05A22}
    .nt-tip::before{content:'';position:absolute;width:14px;height:14px;transform:rotate(45deg);
      background:rgba(255,255,255,0.8);border:1px solid rgba(255,255,255,0.95);left:var(--ax,28px)}
    .nt-tip.below::before{top:-8px;border-right:none;border-bottom:none}
    .nt-tip.above::before{bottom:-8px;border-left:none;border-top:none}
    .nt-ring{position:fixed;z-index:94;border-radius:12px;pointer-events:none;box-shadow:0 0 0 2px rgba(240,90,34,0.85),0 0 0 7px rgba(240,90,34,0.16);
      transition:all .3s cubic-bezier(0.23,1,0.32,1)}
    @media (prefers-reduced-motion:reduce){.nt-tip,.nt-ring{transition:none}}
  `;
  document.head.appendChild(css);

  const visible = el => { if (!el) return false; const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !el.closest('[hidden]'); };
  let tip = null, ring = null, at = -1;
  function close() {
    if (tip) { tip.remove(); tip = null; }
    if (ring) { ring.remove(); ring = null; }
    at = -1;
  }
  function place(el) {
    if (!tip) return;
    const r = el.getBoundingClientRect(), W = window.innerWidth, H = window.innerHeight, tw = tip.offsetWidth, th = tip.offsetHeight;
    const below = r.bottom + th + 18 < H || r.top < th + 18;
    const left = Math.max(12, Math.min(W - tw - 12, r.left));
    tip.style.left = left + 'px';
    tip.style.top = (below ? r.bottom + 14 : r.top - th - 14) + 'px';
    tip.classList.toggle('below', below); tip.classList.toggle('above', !below);
    tip.style.setProperty('--ax', Math.max(16, Math.min(tw - 30, r.left + Math.min(r.width, 60) / 2 - left - 7)) + 'px');
    if (ring) Object.assign(ring.style, { left: r.left - 5 + 'px', top: r.top - 5 + 'px', width: r.width + 10 + 'px', height: r.height + 10 + 'px' });
  }
  function show(i) {
    const [sel, title, text, fallback, when] = steps[i];
    let el = document.querySelector(sel), later = false;
    if (!visible(el) && fallback) { el = document.querySelector(fallback); later = true; }   // not here yet: say where and when
    if (!visible(el)) return false;
    close(); at = i;
    const r = el.getBoundingClientRect();
    if (r.top < 60 || r.bottom > window.innerHeight - 60) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    ring = document.createElement('div'); ring.className = 'nt-ring'; document.body.appendChild(ring);
    tip = document.createElement('div'); tip.className = 'nt-tip'; tip.setAttribute('role', 'dialog'); tip.setAttribute('aria-label', title);
    const hasBack = i > 0;
    const last = !steps.some((s, j) => j > i && !state.done.includes(s[0]));
    tip.innerHTML = `<button class="x" aria-label="Close">\u00d7</button><b></b><p></p>
      <div class="foot"><span class="n">${i + 1} of ${steps.length}</span>${hasBack ? '<button class="b back">Back</button>' : ''}
        <button class="b go">${last ? 'Got it' : 'Next'}</button></div>
      <label><input type="checkbox"> Don\u2019t show again</label>`;
    tip.querySelector('b').textContent = title;
    tip.querySelector('p').textContent = later ? `${when}: ${text.charAt(0).toLowerCase()}${text.slice(1)}` : text;
    document.body.appendChild(tip);
    place(el);
    requestAnimationFrame(() => tip && tip.classList.add('on'));
    tip.querySelector('.x').onclick = () => { dismissed = true; close(); };
    tip.querySelector('.go').onclick = () => {
      if (!state.done.includes(sel)) state.done.push(sel);
      store(state); close(); next();
    };
    const back = tip.querySelector('.back');
    if (back) back.onclick = () => { state.done = state.done.filter(s => s !== steps[i - 1][0]); show(i - 1); };
    tip.querySelector('input').onchange = e => { state.off = e.target.checked; store(state); if (state.off) close(); };
    return true;
  }
  // Strictly in order: the next step not yet done — and if its control isn't on
  // screen yet (a scene before you've scanned), wait for it rather than skipping ahead.
  function next() {
    if (state.off || dismissed || tip || document.visibilityState !== 'visible') return;
    const i = steps.findIndex(s => !state.done.includes(s[0]));
    if (i >= 0) show(i);
  }
  // Steps wait for their controls: check now and then, and follow the page as it moves.
  setInterval(next, 1200);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') { if (!state.off) { state.done = []; dismissed = false; } setTimeout(next, 400); }
    else close();
  });
  window.addEventListener('resize', () => { if (at >= 0) { const el = document.querySelector(steps[at][0]); if (visible(el)) place(el); else close(); } });
  document.addEventListener('scroll', () => { if (at >= 0) { const el = document.querySelector(steps[at][0]); if (visible(el)) place(el); } }, true);
  // ← in the top bar closes a note like any pop-up.
  const prevBack = window.__neededBack;
  window.__neededBack = () => { if (tip) { dismissed = true; close(); return true; } return prevBack ? prevBack() : false; };
  window.__neededHints = {
    replay() { state = { done: [] }; store(state); dismissed = false; close(); next(); },
    reset() { state = { done: [] }; store(state); },
  };
  setTimeout(next, 900);
})();
