/* Needed Tools — the one loading pill for the whole suite, in every tool
   and on Home: a label, and a percentage when there is one (an animated
   bar when there isn't). window.__neededLoad.start(label) / .set(f) / .done(). */
(function () {
  if (window.__neededLoad) return;
  const style = document.createElement('style');
  style.textContent = `
    .needed-load { position: fixed; left: 50%; top: 14px; transform: translate(-50%, -8px); z-index: 90; display: flex; align-items: center; gap: 12px;
      padding: 10px 16px; border-radius: 100px; font: 13px Raleway, sans-serif; color: #141414; opacity: 0; pointer-events: none;
      background: linear-gradient(160deg, rgba(255,255,255,0.8), rgba(255,255,255,0.55)); border: 1px solid rgba(255,255,255,0.9);
      box-shadow: inset 0 1px 0 #fff, 0 12px 36px rgba(160,70,20,0.16); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px);
      transition: opacity .25s cubic-bezier(0.23,1,0.32,1), transform .25s cubic-bezier(0.23,1,0.32,1); }
    .needed-load.on { opacity: 1; transform: translate(-50%, 0); }
    .needed-load i { position: relative; width: 160px; height: 4px; border-radius: 4px; background: rgba(28,28,28,0.08); overflow: hidden; }
    .needed-load i b { position: absolute; left: 0; top: 0; bottom: 0; width: 0; background: #F05A22; border-radius: 4px; transition: width .2s linear; }
    .needed-load em { font-style: normal; font-variant-numeric: tabular-nums; color: #7a5a48; min-width: 36px; }
    .needed-load.unknown em { min-width: 0; }
    .needed-load.unknown i b { width: 38% !important; animation: nt-slide 1.1s cubic-bezier(0.45,0,0.55,1) infinite; }
    @keyframes nt-slide { from { transform: translateX(-100%); } to { transform: translateX(270%); } }
  `;
  (document.head || document.documentElement).appendChild(style);

  const pill = document.createElement('div');
  pill.className = 'needed-load';
  pill.setAttribute('role', 'status');
  pill.innerHTML = '<span></span><i><b></b></i><em></em>';
  document.body.appendChild(pill);
  let busy = 0, showT = null, hideT = null;
  const L = window.__neededLoad = {
    get busy() { return busy > 0; },
    start(label) {
      busy++; clearTimeout(hideT);
      pill.querySelector('span').textContent = label || 'Bringing it in';
      L.set(null);
      clearTimeout(showT); showT = setTimeout(() => { if (busy > 0) pill.classList.add('on'); }, 250);   // quick jobs never flash it up
    },
    set(f) {
      const bar = pill.querySelector('b'), pct = pill.querySelector('em');
      if (f == null || !isFinite(f)) { pill.classList.add('unknown'); pct.textContent = ''; return; }
      pill.classList.remove('unknown');
      const n = Math.max(0, Math.min(100, Math.round(f * 100)));
      bar.style.width = n + '%'; pct.textContent = n + '%';
    },
    done() {
      busy = Math.max(0, busy - 1);
      if (busy) return;
      clearTimeout(showT);
      if (pill.classList.contains('on')) { L.set(1); hideT = setTimeout(() => pill.classList.remove('on'), 380); }
    },
  };
})();
