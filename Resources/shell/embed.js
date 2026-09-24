/* Needed Tools — what every tool gets inside the app:
   the apricot glow, full width at any window size, pop-ups that close
   when you click outside them, and ← closing whatever's open first. */
(function () {
  if (window.__neededEmbed) return;
  window.__neededEmbed = true;
  document.documentElement.classList.add('in-needed-tools');

  let css = `
    html.in-needed-tools { --bg: #fbf3ed; }
    html.in-needed-tools body { background: #fbf3ed; }
    html.in-needed-tools body::before { content: ''; position: fixed; inset: 0; z-index: -1; pointer-events: none;
      background: radial-gradient(ellipse 72% 78% at 50% 54%, #f7bf99 0%, #f9cfb1 26%, #fbdfca 50%, #fcebdf 72%, #fdf5ef 100%); opacity: 0.85; }
    /* fill the window, however big it is */
    html.in-needed-tools main { max-width: none !important; }
    html.in-needed-tools body > header, html.in-needed-tools main, html.in-needed-tools .bar { padding-left: clamp(24px, 3vw, 56px) !important; padding-right: clamp(24px, 3vw, 56px) !important; }
    /* the bar along the bottom: glass over the glow */
    html.in-needed-tools .bar { background: rgba(252,243,237,0.72) !important; -webkit-backdrop-filter: blur(22px) saturate(1.5); backdrop-filter: blur(22px) saturate(1.5);
      border-top: 1px solid rgba(255,255,255,0.6) !important; }
    html.in-needed-tools header { background: transparent !important; border-bottom-color: rgba(28,28,28,0.06) !important; }
  `;
  // ---- a touch more contrast and gloss, same look
  css += `
    html.in-needed-tools { --ink: #141414; }
    html.in-needed-tools .pill { border-color: rgba(28,28,28,0.12); box-shadow: inset 0 1px 0 rgba(255,255,255,0.8), 0 1px 2px rgba(80,30,10,0.05); }
    html.in-needed-tools .pill.solid, html.in-needed-tools .pill.solid:disabled { background: linear-gradient(180deg, #2b2b2b, #111) !important; border-color: #111 !important;
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.14), 0 2px 8px rgba(20,20,20,0.18); }
    html.in-needed-tools .chip.on { box-shadow: inset 0 1px 0 rgba(255,255,255,0.14); }
    html.in-needed-tools main input, html.in-needed-tools main textarea, html.in-needed-tools main select { box-shadow: inset 0 1px 0 rgba(255,255,255,0.6); }

    /* ---- players in the original's shape: no black box round a tall reel */
    html.in-needed-tools .stage { background: transparent !important; overflow: visible !important; }
    html.in-needed-tools .stage video { border-radius: 12px; box-shadow: 0 18px 50px rgba(80,30,10,0.18), 0 0 0 0.5px rgba(0,0,0,0.12); background: #000; }
    html.in-needed-tools .pvstage { background: transparent !important; }
    html.in-needed-tools .pvstage canvas { border-radius: 10px; box-shadow: 0 14px 40px rgba(80,30,10,0.16); }

    /* ---- the Vault's viewer: the picture floating, details on glass */
    html.in-needed-tools #itemModal { background: rgba(251,243,237,0.3) !important; -webkit-backdrop-filter: blur(26px) saturate(1.3); backdrop-filter: blur(26px) saturate(1.3); }
    html.in-needed-tools #itemModal .itemwrap { background: transparent !important; box-shadow: none !important; border: none !important; }
    html.in-needed-tools #itemModal .itemmedia { background: transparent !important; min-height: 0 !important; overflow: visible !important; }
    html.in-needed-tools #itemModal .itemmedia img, html.in-needed-tools #itemModal .itemmedia video {
      border-radius: 12px; box-shadow: 0 30px 90px rgba(80,30,10,0.28); max-height: 78vh; }
    html.in-needed-tools #itemModal .iteminfo {
      background: linear-gradient(160deg, rgba(255,255,255,0.62), rgba(255,255,255,0.34)); border: 1px solid rgba(255,255,255,0.7); border-radius: 20px;
      box-shadow: inset 0 1.5px 0 rgba(255,255,255,0.95), 0 24px 70px rgba(160,70,20,0.14); padding: 20px !important;
      -webkit-backdrop-filter: blur(30px) saturate(1.6); backdrop-filter: blur(30px) saturate(1.6); }

    /* no focus ring round the players — they still take the keyboard */
    html.in-needed-tools .stage, html.in-needed-tools .stage:focus, html.in-needed-tools .stage:focus-visible,
    html.in-needed-tools video:focus, html.in-needed-tools video:focus-visible, html.in-needed-tools .pvstage:focus,
    html.in-needed-tools canvas:focus, html.in-needed-tools [tabindex]:focus-visible.stage,
    html.in-needed-tools .stage.keys, html.in-needed-tools .pvstage.keys, html.in-needed-tools .pvstage:focus-within { outline: none !important; box-shadow: none !important; }
  `;
  const style = document.createElement('style');
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  const L = window.__neededLoad;             // the one loading pill (load.js)

  // Bringing a film in: how far along it is, until it's ready to scrub.
  const film = document.getElementById('video');
  if (film) {
    let loading = false;
    const buffered = () => { try { const d = film.duration; if (!d || !isFinite(d) || !film.buffered.length) return 0;
      return film.buffered.end(film.buffered.length - 1) / d; } catch (e) { return 0; } };
    film.addEventListener('loadstart', () => { if (!film.currentSrc && !film.src) return; if (!loading) { loading = true; L.start('Bringing it in'); } L.set(0.03); });
    film.addEventListener('loadedmetadata', () => loading && L.set(Math.max(0.35, buffered())));
    film.addEventListener('progress', () => loading && L.set(Math.max(0.35, buffered())));
    const end = () => { if (loading) { loading = false; L.done(); } };
    film.addEventListener('canplay', end);
    film.addEventListener('error', end);
    film.addEventListener('emptied', () => { if (loading && !film.src) end(); });
  }

  // Everything slow the tools ask the Mac to do shows the same pill.
  const SLOW = {
    lookup: 'Finding it', preview: 'Bringing it in', pull: 'Bringing it in', importFiles: 'Adding to your vault',
    makeGif: 'Making the GIF', makeClip: 'Making the MP4', vaultMove: 'Moving',
    scan: 'Scanning the cards', build: 'Copying and checking',
    exportPdf: 'Making the PDF', moodBoard: 'Making the mood board', previewPdf: 'Making the preview', importPdf: 'Reading the PDF', sendMail: 'Sending',
  };
  const handlers = window.webkit && window.webkit.messageHandlers;
  const files = handlers && handlers.files;

  // When one finishes, macOS says so — a notification, even if you're in another
  // app. Only on success; a sound too when it took a while.
  const plural = (n, one) => `${n} ${one}${n === 1 ? '' : 's'}`;
  const DONE = {
    preview: r => r && r.ok !== false && ['Footage is in', 'The link is ready to play and grab from.'],
    pull: r => r && r.ok && ['Footage is in', 'That section is ready in the Vault.'],
    importFiles: r => r && r.added && ['Added to your vault', `${plural(r.added, 'file')} added to this project.`],
    makeGif: r => r && r.ok && ['GIF saved', r.name || 'Saved into your project.'],
    makeClip: r => r && r.ok && ['MP4 saved', r.name || 'Saved into your project.'],
    scan: r => r && r.ok !== false && ['Cards scanned', 'Every clip is read and grouped into scenes.'],
    build: r => r && !r.cancelled && (r.failed && r.failed.length
      ? ['Sort finished — check it', `${r.copied} of ${r.total} copied; ${plural(r.failed.length, 'file')} didn't match the card.`]
      : ['Sort finished', `All ${r.copied} files copied and checked against the cards.`]),
    exportPdf: r => r && r.ok !== false && ['PDF made', r.name || 'Saved into your project.'],
    importPdf: r => r && r.ok !== false && ['Read it', 'The PDF is in.'],
    sendMail: (r, m) => r && r.ok && ['Sent', `${m && m.to ? 'To ' + m.to + ' — ' : ''}a copy is in your inbox.`],
    moodBoard: r => r && r.ok && ['Mood board saved', `${r.name} — ${plural(r.pages, 'page')}.`],
  };
  const shellBridge = handlers && handlers.shell;
  const tell = (title, body, sound) => { try { shellBridge && shellBridge.postMessage({ action: 'notify', title, body, sound: !!sound }); } catch (e) { /* fine */ } };
  // Stills save one file at a time: one notification for the batch, once it's quiet.
  let stillsSaved = 0, stillsT = null;
  const stillSaved = () => {
    stillsSaved++; clearTimeout(stillsT);
    stillsT = setTimeout(() => { tell('Stills saved', `${plural(stillsSaved, 'still')} saved into your project.`); stillsSaved = 0; }, 1500);
  };
  if (files && files.postMessage) {
    const send = files.postMessage.bind(files);
    try {
      files.postMessage = msg => {
        const action = msg && msg.action, label = SLOW[action];
        const p = send(msg);
        if (label && p && p.then) { L.start(label); p.then(() => L.done(), () => L.done()); }
        if (p && p.then && (DONE[action] || action === 'saveFile')) {
          const began = Date.now();
          p.then(r => {
            if (action === 'saveFile') {
              if (r && r.ok) { if (msg.folder === 'Sheets') tell('Contact sheet saved', r.name || 'Saved into your project.'); else stillSaved(); }
              return;
            }
            const said = DONE[action](r, msg);
            if (said) tell(said[0], said[1], Date.now() - began > 8000);
          }, () => {});
        }
        // jobs that report how far along they are (GIFs, MP4s, Sort's copying)
        if (action === 'progress' && p && p.then) p.then(r => {
          const f = r && (typeof r.progress === 'number' ? r.progress : typeof r.fraction === 'number' ? r.fraction : typeof r.pct === 'number' ? r.pct / 100 : null);
          if (f != null && L.busy) L.set(f);
        }, () => {});
        return p;
      };
    } catch (e) { /* this view won't let us watch — the tools still work, just without the pill */ }
  }

  // Pop-ups in the tools, and the button that closes each one.
  // (The Vault's idea editor is left out on purpose: a stray click shouldn't lose a half-written note.)
  const CLOSERS = [['cropModal', 'cropDone'], ['itemModal', 'itemClose'], ['drawer', 'drawerClose'], ['addModal', 'addCancel'], ['openModal', 'openCancel'], ['sendVeil', 'sCancel']];
  const openOne = () => {
    for (const [box, btn] of CLOSERS) {
      const el = document.getElementById(box);
      if (el && !el.hidden && getComputedStyle(el).display !== 'none') return [el, document.getElementById(btn)];
    }
    return null;
  };
  // Click the blur around a pop-up and it closes, same as its Done button —
  // and that click doesn't then land on whatever was underneath the pop-up.
  let swallowClick = false;
  document.addEventListener('mousedown', e => {
    const o = openOne();
    if (o && e.target === o[0] && o[1]) {
      e.preventDefault(); o[1].click();
      swallowClick = true; setTimeout(() => { swallowClick = false; }, 600);
    }
  }, true);
  document.addEventListener('click', e => {
    if (swallowClick) { swallowClick = false; e.stopPropagation(); e.preventDefault(); }
  }, true);
  // ← in the top bar closes what's open before going back a tab.
  window.__neededBack = () => {
    const o = openOne();
    if (o && o[1]) { o[1].click(); return true; }
    return false;
  };
})();
