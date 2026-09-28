/* Needed Direct Vault — persistent phone queue, same-origin Wi-Fi transfers and confirmed receipts. */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var get = function (k, d) { try { var v = localStorage.getItem('nv.' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } };
  var put = function (k, v) { try { localStorage.setItem('nv.' + k, JSON.stringify(v)); } catch (e) {} };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  function toast(t, ms) { var e = $('toast'); e.textContent = t; e.classList.add('show'); clearTimeout(toast.t); toast.t = setTimeout(function () { e.classList.remove('show'); }, ms || 2600); }

  /* ---- where it's opened: Safari (show how to make it an app) or from the Home Screen */
  var ua = navigator.userAgent || '';
  var IOS = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var APP = (window.navigator.standalone === true) || (window.matchMedia && matchMedia('(display-mode: standalone)').matches);
  var INAPP = /FBAN|FBAV|Instagram|Line\/|GSA\//.test(ua);     // a browser inside another app: no Add to Home Screen there

  /* ---- projects: from your Mac's QR code (?p=Lexus|Nike&m=Studio), plus any you type here */
  // Kept on the phone, so they're still here when it's opened from the Home Screen; a scan brings them up to date.
  var params = new URLSearchParams(location.search);
  function fromLink(q) { return (q.get('p') || '').split('|').map(function (s) { return s.trim(); }).filter(Boolean); }
  var fromMac = get('macProjects', []);
  function takeMac(list, mac) {
    if (!list.length) return [];
    var before = get('macProjects', []), fresh = before.length ? list.filter(function (p) { return before.indexOf(p) < 0; }) : [];
    fromMac = list; put('macProjects', list); put('macAt', Date.now());
    if (mac) put('mac', mac);
    put('newProjects', fresh.concat(get('newProjects', []).filter(function (p) { return list.indexOf(p) >= 0 && fresh.indexOf(p) < 0; })).slice(0, 20));
    return fresh;
  }
  // The link the page was opened with (the Home Screen keeps it) counts once — a later scan isn't undone by it.
  if (fromLink(params).length && get('linkSeen', '') !== params.get('p')) { put('linkSeen', params.get('p')); takeMac(fromLink(params), params.get('m') || ''); }
  // Direct mode runs on the Mac's own origin: no cross-origin or Photos transfer.
  var DIRECT_KEY = get('directKey', '');
  function readDirectKey() {
    var m = /[#&]k=([A-Za-z0-9]{20,64})/.exec(location.hash);
    if (m) { DIRECT_KEY = m[1]; put('directKey', DIRECT_KEY); history.replaceState(null, '', location.pathname); }
  }
  readDirectKey();
  addEventListener('hashchange', function () { readDirectKey(); if (db) pull(); });
  function pull() {
    if (!DIRECT_KEY) { toast('Scan the Direct Wi-Fi QR code in Needed Tools on your Mac', 6000); return Promise.resolve(false); }
    var ctl = new AbortController(), timer = setTimeout(function () { ctl.abort(); }, 8000);
    return fetch('/api/state', { headers: { 'X-Key': DIRECT_KEY }, cache: 'no-store', signal: ctl.signal }).then(function (r) {
      if (!r.ok) throw new Error(r.status === 401 ? 'Scan the Mac’s Direct Wi-Fi code again' : 'Could not reach the Mac');
      return r.json();
    }).then(function (r) {
      takeMac((r.projects || []).map(function (p) { return p.n; }), r.mac || 'your Mac');
      MAC = r.mac || 'your Mac';
      if (!S.project) { S.project = r.current || fromMac[0] || ''; put('project', S.project); }
      if (!r.vault) toast('Choose a vault folder in Needed Tools on your Mac first', 5000);
      draw(); return true;
    }).catch(function (e) { toast(e.name === 'AbortError' ? 'Mac not reachable — check the Wi-Fi and keep Needed Tools open' : e.message, 5000); return false; })
      .finally(function () { clearTimeout(timer); });
  }
  var MAC = get('mac', 'your Mac');
  function projects() {
    var mine = get('projects', []), all = [];
    fromMac.concat(mine).forEach(function (p) { if (p && all.indexOf(p) < 0) all.push(p); });
    return all;
  }
  function keepProject(p) { var mine = get('projects', []); if (mine.indexOf(p) < 0 && fromMac.indexOf(p) < 0) { mine.unshift(p); put('projects', mine.slice(0, 60)); } }
  var S = { project: get('project', '') || fromMac[0] || '', kind: 'all', q: '', grabGo: get('grabGo', ''), view: get('view', 'days'), only: '', items: [] };

  /* ---- the phone's own store */
  var db = null;
  function open() {
    return new Promise(function (ok, no) {
      if (!window.indexedDB) return no(new Error('This browser can’t keep files'));
      var r = indexedDB.open('needed-vault-direct', 1);
      r.onupgradeneeded = function () { var s = r.result.createObjectStore('items', { keyPath: 'id' }); s.createIndex('at', 'at'); };
      r.onsuccess = function () { db = r.result; ok(db); };
      r.onerror = function () { no(r.error); };
    });
  }
  function tx(mode) { return db.transaction('items', mode).objectStore('items'); }
  function all() { return new Promise(function (ok, no) { var r = tx('readonly').getAll(); r.onsuccess = function () { ok(r.result || []); }; r.onerror = function () { no(r.error); }; }); }
  function save(it) { return new Promise(function (ok, no) { var t = db.transaction('items', 'readwrite'); t.objectStore('items').put(it); t.oncomplete = function () { ok(it); }; t.onerror = t.onabort = function () { no(t.error || new Error('Could not save on this phone')); }; }); }
  function drop(id) { return new Promise(function (ok) { var r = tx('readwrite').delete(id); r.onsuccess = r.onerror = function () { ok(); }; }); }
  function refresh() {
    return all().then(function (list) {
      list.sort(function (a, b) { return b.at - a.at; }); S.items = list;
      var ids = {}; list.forEach(function (it) { ids[it.id] = 1; });
      Object.keys(urls).forEach(function (id) { if (!ids[id]) { URL.revokeObjectURL(urls[id]); delete urls[id]; } });
      draw(); tidy();
    });
  }
  if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(function () {});

  /* ---- the Home Screen guide */
  function showInstall(force) {
    var need = false;
    $('install').classList.add('off'); $('app').classList.remove('off');
    if (!need) return;
    $('instIOS').classList.toggle('off', !IOS || INAPP);
    $('instInApp').classList.toggle('off', !INAPP);
    $('instOther').classList.toggle('off', IOS || INAPP);
    $('instMac').textContent = fromMac.length ? fromMac.length + ' project' + (fromMac.length === 1 ? '' : 's') + ' from ' + MAC + ' come with it.' : '';
  }
  $('instSkip').addEventListener('click', function () { put('skipInstall', true); showInstall(false); refresh(); });
  var deferred = null;                                          // Android / Chrome: its own Install button
  addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); deferred = e; $('instBtn').classList.remove('off'); });
  $('instBtn').addEventListener('click', function () { if (deferred) { deferred.prompt(); deferred = null; } });

  /* ---- drawing: the feed — your grabs by day, each picture its own shape, never cropped */
  function kindOf(type, name) {
    if (/gif$/i.test(type) || /\.gif$/i.test(name)) return 'gif';
    if (/^video\//.test(type) || /\.(mov|mp4|m4v)$/i.test(name)) return 'clip';
    return 'still';
  }
  function waiting() { return S.items.filter(function (it) { return !it.received && it.blob; }); }
  function receiptStatus(it) { return it.received ? 'received by Mac' : it.directQueued ? 'queued — tap Retry' : 'ready to send'; }
  function listNow() {
    var s = S.q.trim().toLowerCase();
    return S.items.filter(function (it) {
      if (S.only && it.project !== S.only) return false;
      if (S.kind !== 'all' && it.kind !== S.kind) return false;
      return !s || (it.name + ' ' + it.project + ' ' + (it.tags || []).join(' ')).toLowerCase().indexOf(s) >= 0;
    });
  }
  // A picture for the feed: its preview (made on this phone), else the small first one.
  var urls = {};
  function picURL(it) {
    if (it.pv) return urls[it.id] || (urls[it.id] = URL.createObjectURL(it.pv));
    return it.thumb || '';
  }
  function dayName(t) {
    var d = new Date(t), now = new Date(), y = new Date(now); y.setDate(now.getDate() - 1);
    if (d.toDateString() === now.toDateString()) return 'Today';
    if (d.toDateString() === y.toDateString()) return 'Yesterday';
    return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' }) + (d.getFullYear() !== now.getFullYear() ? ' ' + d.getFullYear() : '');
  }
  var PLAY = '<svg width="10" height="12" viewBox="0 0 10 12" aria-hidden="true"><path d="M1 1l8 5-8 5z" fill="#141414"/></svg>';
  function shot(it, i, lead) {
    var a = Math.min(3, Math.max(0.3, it.a || 1.4)), src = picURL(it);
    return '<button class="shot' + (lead ? ' lead' : '') + '" data-i="' + i + '" style="aspect-ratio:' + a.toFixed(4) + '" aria-label="' + esc(it.name) + '">'
      + (src ? '<img alt="" loading="lazy" decoding="async" src="' + esc(src) + '">' : '')
      + (it.kind === 'clip' ? '<span class="kind">' + PLAY + '</span>' : it.kind === 'gif' ? '<span class="kind gif">GIF</span>' : '')
      + (it.sent ? '' : '<span class="dot" title="Not sent yet"></span>') + '</button>';
  }
  // One run of grabs: a wide one leads across the width; the rest fall into two columns by height.
  function group(list, idx) {
    var h = '', rest = list, colW = 1, cols = [[], []], hs = [0, 0];
    if ((list[0].a || 1.4) >= 0.72) { h += shot(list[0], idx[0], true); rest = list.slice(1); idx = idx.slice(1); }
    if (rest.length === 1) return h + shot(rest[0], idx[0], true);
    rest.forEach(function (it, k) { var c = hs[0] <= hs[1] ? 0 : 1; cols[c].push(shot(it, idx[k])); hs[c] += colW / Math.min(3, Math.max(0.3, it.a || 1.4)) + 0.02; });
    return h + (rest.length ? '<div class="cols"><div class="col">' + cols[0].join('') + '</div><div class="col">' + cols[1].join('') + '</div></div>' : '');
  }
  function drawFeed() {
    var list = listNow(), days = [], out = '';
    list.forEach(function (it, i) {
      var dn = dayName(it.at), d = days[days.length - 1];
      if (!d || d.name !== dn) days.push(d = { name: dn, runs: [] });
      var r = d.runs[d.runs.length - 1];
      if (!r || r.project !== it.project) d.runs.push(r = { project: it.project, items: [], idx: [] });
      r.items.push(it); r.idx.push(i);
    });
    days.forEach(function (d) {
      out += '<section class="day"><h2>' + esc(d.name) + '</h2>';
      d.runs.forEach(function (r) {
        var w = r.items.filter(function (it) { return !it.sent; }).length;
        out += '<div class="run"><div class="runh"><span class="cap">' + esc(r.project) + ' · ' + r.items.length + '</span>' + (w ? '<span class="cap wait">' + w + ' not sent</span>' : '') + '</div>' + group(r.items, r.idx) + '</div>';
      });
      out += '</section>';
    });
    $('feed').innerHTML = out || '<div class="empty">' + (S.q || S.kind !== 'all' ? 'Nothing matches.'
      : S.project ? 'Nothing here yet. <b>Photos</b> or <b>Camera</b> below — it waits on this phone until you Sync it to your Mac.' : 'Pick a project up top — or make one — then add photos and clips.') + '</div>';
  }
  function drawSend() {
    var w = waiting(), n = w.length;
    $('sendBar').classList.toggle('off', !n && !directBusy);
    $('sendN').textContent = directBusy ? 'Sending to ' + MAC : n + ' ready to send';
    $('sendWhere').textContent = 'Direct Wi-Fi · keep this page open';
    $('sendGo').disabled = !!directBusy;
    $('sendGo').textContent = directBusy ? 'Sending…' : w.some(function (it) { return it.directQueued; }) ? 'Retry' : 'Send to Mac';
  }
  // Projects: each one's latest grabs in a row — your Mac's projects first, then any made here.
  function allProjects() {
    var ps = projects();
    S.items.forEach(function (it) { if (ps.indexOf(it.project) < 0) ps.push(it.project); });
    return ps;
  }
  function ago(t) { var m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : m < 60 ? m + ' min ago' : m < 1440 ? Math.round(m / 60) + ' h ago' : new Date(t).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }); }
  function drawProws() {
    var at = get('pulledAt', 0) || get('macAt', 0), fresh = get('newProjects', []);
    $('pairLine').className = 'pairline' + (at ? '' : ' none');
    $('pairLine').innerHTML = at ? '● ' + esc(MAC) + ' · ' + (get('pairKey', '') ? 'up to date ' + esc(ago(at)) : 'paired ' + esc(new Date(at).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }))) + '<button id="plUpdate">' + (get('pairKey', '') ? 'Scan again' : 'Update projects') + '</button>'
      : 'Not paired yet<button id="plUpdate">Pair with your Mac</button>';
    $('prows').innerHTML = allProjects().map(function (p) {
      var mine = S.items.filter(function (it) { return it.project === p; }), w = mine.filter(function (it) { return !it.sent; }).length;
      return '<div class="prow1' + (mine.length ? '' : ' empty') + '"><button class="prowh" data-only="' + esc(p) + '"><span class="n">' + esc(p) + '</span>'
        + (mine.length ? '<span class="c">' + mine.length + '</span>' : '<span class="c">nothing yet</span>') + (w ? '<span class="c wait">' + w + ' TO SYNC</span>' : '')
        + (fresh.indexOf(p) >= 0 ? '<span class="new">NEW</span>' : '') + (S.grabGo === p ? '<span class="gg2">GRAB &amp; GO</span>' : '') + '</button>'
        + (mine.length ? '<div class="pstrip">' + mine.slice(0, 10).map(function (it, k) {
          var src = picURL(it), a = Math.min(2.4, Math.max(0.5, it.a || 1.4));
          return '<button data-pv="' + esc(p) + '" data-i="' + k + '" style="width:' + Math.round(150 * a) + 'px" aria-label="' + esc(it.name) + '">' + (src ? '<img alt="" loading="lazy" src="' + esc(src) + '">' : '') + (it.sent ? '' : '<span class="dot"></span>') + '</button>';
        }).join('') + '</div>' : '') + '</div>';
    }).join('') || '<div class="empty">No projects yet. <b>Pair with your Mac</b> to bring yours across — or make one with the project button up top.</div>';
  }
  // Grab & Go on: one big button, straight in.
  function drawCapture() {
    var p = S.grabGo, today = new Date().toDateString();
    $('capName').textContent = p;
    $('capChips').innerHTML = allProjects().map(function (x) { return '<button class="chip' + (x === p ? ' on' : '') + '" data-gg="' + esc(x) + '">' + esc(x) + '</button>'; }).join('');
    var now = S.items.filter(function (it) { return it.project === p && new Date(it.at).toDateString() === today; }), w = now.filter(function (it) { return !it.sent; }).length;
    $('capRecent').classList.toggle('off', !now.length);
    $('capWait').textContent = w ? w + ' to send' : 'received by Mac';
    $('capStrip').innerHTML = now.slice(0, 12).map(function (it, k) { var src = picURL(it); return '<button data-cap="' + k + '" style="width:' + Math.round(64 * Math.min(2.4, Math.max(0.5, it.a || 1.4))) + 'px" aria-label="' + esc(it.name) + '">' + (src ? '<img alt="" src="' + esc(src) + '">' : '') + '</button>'; }).join('');
  }
  function draw() {
    var on = !!S.grabGo;
    $('pillName').textContent = (on ? S.grabGo : S.project) || 'Projects';
    $('gg').classList.toggle('on', on); $('gg').setAttribute('aria-pressed', on); $('ggWrap').classList.toggle('on', on);
    document.body.classList.toggle('capturing', on);
    $('home').classList.toggle('off', on); $('capture').classList.toggle('off', !on);
    if (on) { drawCapture(); drawSend(); return; }
    var days = S.view !== 'projects' || !!S.only;
    $('title').textContent = S.only || (days ? 'Your grabs' : 'Projects');
    $('viewSeg').classList.toggle('off', !!S.only); $('onlyBack').classList.toggle('off', !S.only);
    [].forEach.call(document.querySelectorAll('#viewSeg [data-v]'), function (b) { b.classList.toggle('on', b.dataset.v === (days ? 'days' : 'projects')); });
    $('daysBox').classList.toggle('off', !days); $('projBox').classList.toggle('off', days);
    var mine = S.items.filter(function (it) { return !S.only || it.project === S.only; });
    $('count').textContent = mine.length ? mine.length + ' here' : '';
    [].forEach.call(document.querySelectorAll('#chips [data-k]'), function (b) { b.classList.toggle('on', b.dataset.k === S.kind); });
    if (days) drawFeed(); else drawProws();
    drawSend();
  }

  /* ---- sheets */
  var SHEETS = ['projSheet', 'addSheet', 'menuSheet', 'sendSheet', 'nudgeSheet'];
  function sheet(id, open) {
    SHEETS.forEach(function (s) { $(s).classList.toggle('on', open && s === id); });
    if (open) $('toast').classList.remove('show');
    $('veil').classList.toggle('on', !!open);
  }
  $('veil').addEventListener('click', function () { sheet(null, false); pending = []; moving = null; });

  /* ---- projects */
  var moving = null;                                            // a grab being moved to another project
  function drawProjects() {
    var ps = allProjects();
    $('projH').textContent = moving ? 'Move it to' : 'Pick a project';
    $('plist').innerHTML = ps.map(function (p) {
      var n = S.items.filter(function (it) { return it.project === p; }).length;
      return '<button class="' + (p === (moving ? moving.project : (S.grabGo || S.project)) ? 'on' : '') + '" data-p="' + esc(p) + '">' + esc(p) + '<small>' + (n ? n + ' here' : '') + '</small></button>';
    }).join('') || '<div class="empty" style="padding:14px 0">No projects yet. Scan the QR code in Needed Tools › Your phone to bring yours across — or type one below.</div>';
  }
  $('pill').addEventListener('click', function () { moving = null; drawProjects(); $('newProj').value = ''; sheet('projSheet', true); });
  function pickProject(p) {
    S.project = p; put('project', p); keepProject(p);
    if (S.grabGo) { S.grabGo = p; put('grabGo', p); }
    S.kind = 'all'; S.q = ''; $('q').value = ''; draw();
  }
  function moveTo(p) {
    var it = moving; moving = null; if (!it || it.project === p) return;
    keepProject(p); it.project = p;
    save(it).then(function () { toast(it.sent ? 'Moved to ' + p + ' here — on your Mac it stays where it was filed' : 'Moved to ' + p); refresh().then(function () { var k = vlist().indexOf(S.items.filter(function (x) { return x.id === it.id; })[0]); if (k >= 0) openView(k); else closeView(); }); });
  }
  $('plist').addEventListener('click', function (e) { var b = e.target.closest('[data-p]'); if (!b) return; sheet(null, false); if (moving) return moveTo(b.dataset.p); pickProject(b.dataset.p); });
  function cleanName(s) { return String(s || '').replace(/[~\/:|#]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80); }
  $('newProjGo').addEventListener('click', function () {
    var p = cleanName($('newProj').value); if (!p) return $('newProj').focus();
    sheet(null, false); if (moving) return moveTo(p); pickProject(p); toast('New project — ' + p);
  });
  $('newProj').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('newProjGo').click(); });
  $('gg').addEventListener('click', function () {
    if (!S.grabGo && !S.project) { drawProjects(); return sheet('projSheet', true); }
    S.grabGo = S.grabGo ? '' : S.project; put('grabGo', S.grabGo);
    toast(S.grabGo ? 'Grab & Go on — ' + S.grabGo : 'Grab & Go off'); draw();
  });

  /* ---- adding: Photos or the camera */
  var pending = [], addTo = '';
  $('photos').addEventListener('click', function () { $('pick').click(); });
  $('camera').addEventListener('click', function () { $('shoot').click(); });
  function picked(e) {
    var files = [].slice.call(e.target.files || []); e.target.value = '';
    if (!files.length) return;
    if (S.grabGo) return keep(files, S.grabGo, []);
    pending = files;
    $('addTitle').textContent = files.length === 1 ? 'One to keep' : files.length + ' to keep';
    $('addPics').innerHTML = files.slice(0, 30).map(function (f) { return /^image\//.test(f.type) ? '<span style="background-image:url(' + URL.createObjectURL(f) + ')"></span>' : '<span>clip</span>'; }).join('');
    addTo = S.project; drawAddProjects(); $('addTags').value = ''; $('addNew').value = ''; drawTagChips();
    sheet('addSheet', true);
  }
  $('pick').addEventListener('change', picked);
  $('shoot').addEventListener('change', picked);
  function drawAddProjects() {
    $('addProjects').innerHTML = allProjects().map(function (p) { return '<button class="chip' + (p === addTo ? ' on' : '') + '" data-to="' + esc(p) + '">' + esc(p) + '</button>'; }).join('');
    $('addGo').textContent = addTo ? 'Keep for ' + addTo : 'Pick a project';
    $('addGo').disabled = !addTo;
  }
  // Your recent tags, one tap each.
  function recentTags() {
    var n = {}; S.items.slice(0, 200).forEach(function (it) { (it.tags || []).forEach(function (t) { n[t] = (n[t] || 0) + 1; }); });
    return Object.keys(n).sort(function (a, b) { return n[b] - n[a]; }).slice(0, 10);
  }
  function typedTags() { return $('addTags').value.split(/[\s,#]+/).map(cleanName).filter(Boolean); }
  function drawTagChips() {
    var have = typedTags(), rec = recentTags();
    $('addTagChips').innerHTML = rec.map(function (t) { return '<button class="chip' + (have.indexOf(t) >= 0 ? ' on' : '') + '" data-tag="' + esc(t) + '">#' + esc(t) + '</button>'; }).join('');
    $('addTagChips').classList.toggle('off', !rec.length);
    $('addTagChips').previousElementSibling.classList.toggle('off', !rec.length);
  }
  $('addTagChips').addEventListener('click', function (e) {
    var b = e.target.closest('[data-tag]'); if (!b) return;
    var t = b.dataset.tag, have = typedTags(), i = have.indexOf(t);
    if (i >= 0) have.splice(i, 1); else have.push(t);
    $('addTags').value = have.join(', '); drawTagChips();
  });
  $('addTags').addEventListener('input', drawTagChips);
  $('addProjects').addEventListener('click', function (e) { var b = e.target.closest('[data-to]'); if (b) { addTo = b.dataset.to; $('addNew').value = ''; drawAddProjects(); } });
  $('addNew').addEventListener('input', function () { var p = cleanName($('addNew').value); if (p) { addTo = p; } else addTo = S.project; drawAddProjects(); });
  $('addCancel').addEventListener('click', function () { pending = []; sheet(null, false); });
  $('addGo').addEventListener('click', function () {
    if (!addTo || !pending.length) return;
    var tags = $('addTags').value.split(/[\s,#]+/).map(cleanName).filter(Boolean);
    var files = pending; pending = []; sheet(null, false);
    keepProject(addTo);
    keep(files, addTo, tags);
  });

  function stampName(f) {
    var ext = (f.name && /\.[A-Za-z0-9]{2,5}$/.test(f.name)) ? f.name.split('.').pop().toLowerCase() : ((f.type.split('/')[1] || 'jpg').replace('jpeg', 'jpg').replace('quicktime', 'mov'));
    var base = (f.name || '').replace(/\.[^.]+$/, '');
    if (!base || /^(image|video|photo|img|capturedimage)$/i.test(base)) {
      var d = new Date(), z = function (n) { return ('0' + n).slice(-2); };
      base = 'Phone ' + d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate()) + ' ' + z(d.getHours()) + '.' + z(d.getMinutes()) + '.' + z(d.getSeconds());
    }
    return cleanName(base) + '.' + ext;
  }
  // The preview this phone keeps: sharp enough to fill the screen, a fraction of the size.
  // Keep originals: completing the share sheet does not confirm receipt by the Mac.
  var PV = 1600;
  function thumbOf(f) {
    if (/^video\//.test(f.type)) return videoThumb(f);
    return new Promise(function (ok) {
      var u = URL.createObjectURL(f), img = new Image(), done = false;
      var fin = function (r) { if (done) return; done = true; URL.revokeObjectURL(u); ok(r); };
      img.onload = function () { shrink(img, img.naturalWidth, img.naturalHeight).then(fin, function () { fin({ pv: null, a: 1.4 }); }); };
      img.onerror = function () { fin({ pv: null, a: 1.4 }); };
      setTimeout(function () { fin({ pv: null, a: 1.4 }); }, 8000);
      img.src = u;
    });
  }
  function shrink(src, w, h) {
    return new Promise(function (ok, no) {
      if (!w || !h) return no(new Error('empty'));
      var c = document.createElement('canvas'), s = Math.min(1, PV / Math.max(w, h)); c.width = Math.max(1, Math.round(w * s)); c.height = Math.max(1, Math.round(h * s));
      c.getContext('2d').drawImage(src, 0, 0, c.width, c.height);
      c.toBlob(function (b) { if (b) ok({ pv: b, a: w / h }); else no(new Error('no preview')); }, 'image/jpeg', 0.84);
    });
  }
  function videoThumb(f) {
    return new Promise(function (ok) {
      var v = document.createElement('video'), u = URL.createObjectURL(f), done = false;
      var fin = function (r) { if (done) return; done = true; URL.revokeObjectURL(u); ok(r); };
      v.muted = true; v.playsInline = true; v.preload = 'metadata'; v.src = u;
      v.onloadeddata = function () { try { v.currentTime = Math.min(0.5, (v.duration || 1) / 3); } catch (e) { fin({ pv: null, a: 1.78 }); } };
      v.onseeked = function () { shrink(v, v.videoWidth, v.videoHeight).then(fin, function () { fin({ pv: null, a: 1.78 }); }); };
      v.onerror = function () { fin({ pv: null, a: 1.78 }); };
      setTimeout(function () { fin({ pv: null, a: 1.78 }); }, 5000);
    });
  }
  // In the background: generate previews without deleting unconfirmed originals.
  var tidying = false;
  function tidy() {
    if (tidying || !db) return;
    var todo = S.items.filter(function (it) { return !it.pv && it.blob; });
    if (!todo.length) return;
    tidying = true;
    var k = 0, changed = false;
    (function next() {
      if (k >= todo.length) { tidying = false; if (changed) refresh(); return; }
      var it = todo[k++];
      (it.pv ? Promise.resolve(null) : thumbOf(it.blob)).then(function (t) {
        if (t && t.pv) { it.pv = t.pv; it.a = t.a || it.a; it.thumb = ''; }
        changed = true;
        return save(it);
      }).catch(function () {}).then(function () { setTimeout(next, 30); });
    })();
  }
  function keep(files, project, tags) {
    var i = 0, n = files.length;
    $('prog').classList.add('on'); $('progBar').style.width = '0%';
    function next() {
      if (i >= n) return Promise.resolve();
      var f = files[i];
      return thumbOf(f).then(function (t) {
        var it = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 7), blob: f, type: f.type || '', name: stampName(f), kind: kindOf(f.type || '', f.name || ''),
                   project: project, tags: tags, at: Date.now(), sent: 0, pv: t.pv, thumb: '', a: t.a, bytes: f.size };
        return save(it);
      }).then(function () { i++; $('progBar').style.width = Math.round(i / n * 100) + '%'; return next(); });
    }
    next().then(function () {
      $('prog').classList.remove('on');
      if (project !== S.project && !S.grabGo) { S.project = project; put('project', project); }
      toast((n === 1 ? 'Kept for ' : n + ' kept for ') + project + ' — tap Send to Mac');
      refresh();
    }).catch(function (e) {
      $('prog').classList.remove('on');
      toast(/quota/i.test(String(e && e.name)) ? 'This phone’s out of room for Mobile Vault — send some to your Mac first' : 'Couldn’t keep that one: ' + (e && e.message || e), 4200);
      refresh();
    });
  }

  var BATCH = 25, directBusy = false;
  function directSendOne(it, index, total) {
    return new Promise(function (ok, no) {
      var x = new XMLHttpRequest();
      x.open('POST', '/api/upload?p=' + encodeURIComponent(it.project) + '&name=' + encodeURIComponent(it.name) + '&tags=' + encodeURIComponent((it.tags || []).join(',')) + '&phoneId=' + encodeURIComponent(it.id));
      x.setRequestHeader('X-Key', DIRECT_KEY);
      x.timeout = 180000;
      x.upload.onprogress = function (e) {
        if (e.lengthComputable) $('progBar').style.width = Math.round((index + e.loaded / e.total) / total * 100) + '%';
      };
      x.onload = function () {
        var r; try { r = JSON.parse(x.responseText); } catch (e) {}
        if (x.status === 200 && r && r.ok === true && r.id && r.phoneId === it.id) ok(r);
        else no(new Error(x.status === 401 ? 'Scan the Mac’s Direct Wi-Fi QR code again' : (r && r.error) || 'The Mac did not confirm this file — it remains queued'));
      };
      x.onerror = x.ontimeout = x.onabort = function () { no(new Error('Connection interrupted — keep both devices on the same Wi-Fi, then tap Retry')); };
      x.send(it.blob);
    });
  }
  async function syncItems(w, resume) {
    if (directBusy || !w.length) return;
    directBusy = true; drawSend();
    var done = 0;
    try {
      if (!DIRECT_KEY) throw new Error('Scan the Direct Wi-Fi QR code on your Mac first');
      // Persist retry intent before sending a byte. A closed tab can resume safely.
      if (!resume) for (var it of w) { var queued = Object.assign({}, it, { directQueued: true }); await save(queued); it.directQueued = true; }
      $('prog').classList.add('on'); $('progBar').style.width = '0%';
      for (var i = 0; i < w.length; i++) {
        var it = w[i];
        toast('Sending ' + (i + 1) + ' of ' + w.length + ' to ' + MAC + '…', 180000);
        await directSendOne(it, i, w.length);
        var confirmed = Object.assign({}, it, { received: Date.now(), sent: Date.now(), directQueued: false });
        await save(confirmed); Object.assign(it, confirmed); done++;
      }
      toast(done + ' received by ' + MAC, 5000);
    } catch (e) { toast((done ? done + ' received. ' : '') + e.message, 8000); }
    finally { directBusy = false; $('prog').classList.remove('on'); await refresh(); }
  }
  function resumeDirect() {
    if (!db || directBusy || document.visibilityState !== 'visible') return;
    var w = waiting().filter(function (it) { return it.directQueued; });
    if (w.length) syncItems(w, true);
  }
  $('sendGo').addEventListener('click', function () { syncItems(waiting()); });
  $('mResync').addEventListener('click', function () { sheet(null, false); syncItems(waiting()); });
  $('sendHow').addEventListener('click', function () { sheet('sendSheet', true); });
  $('sendOk').addEventListener('click', function () { sheet(null, false); });
  $('nudgePhotos').addEventListener('click', function () { sheet(null, false); });
  $('nudgeDone').addEventListener('click', function () { sheet(null, false); });

  /* ---- the menu: how it works, room on the phone, make it an app */
  $('mark').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.received; }), bytes = S.items.reduce(function (a, it) { return a + (it.blob ? it.blob.size || it.bytes || 0 : 0) + (it.pv ? it.pv.size || 0 : 0); }, 0);
    $('mSent').textContent = S.items.length + ' here · ' + (bytes / 1048576).toFixed(bytes > 1048576 * 10 ? 0 : 1) + ' MB';
    $('mClear').disabled = !sent.length;
    $('mMac').textContent = MAC;
    $('mHomeRow').classList.toggle('off', APP);
    sheet('menuSheet', true);
  });
  $('mClear').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.received; });
    if (!sent.length || !confirm('Remove the ' + sent.length + ' items previously confirmed by your Mac from this phone? Check that you still have those originals before continuing.')) return;
    Promise.all(sent.map(function (it) { return drop(it.id); })).then(function () { sheet(null, false); toast('Room made on this phone'); refresh(); });
  });
  $('mHome').addEventListener('click', function () { sheet(null, false); showInstall(true); });
  $('mDone').addEventListener('click', function () { sheet(null, false); });

  /* ---- one picture: light, the picture as big as it goes, the rest out of its way */
  var vi = -1, vurl = '', vsrc = listNow;
  function vlist() { return vsrc(); }
  function openView(i) {
    var list = vlist(), it = list[i]; if (!it) return; vi = i;
    var v = $('vPic').querySelector('video'); if (v) v.pause();
    if (vurl) { URL.revokeObjectURL(vurl); vurl = ''; }
    var full = it.blob && (it.kind !== 'still' || !it.pv || it.blob.size < 6e6);     // stills show the preview; clips and GIFs play while they're here
    var src = full ? (vurl = URL.createObjectURL(it.blob)) : picURL(it);
    $('vN').textContent = (i + 1) + ' / ' + list.length;
    $('vPic').innerHTML = it.kind === 'clip' && it.blob ? '<video src="' + src + '" controls playsinline preload="metadata"' + (it.pv ? ' poster="' + esc(picURL(it)) + '"' : '') + '></video>'
      : (src ? '<img alt="" src="' + esc(src) + '">' : '');
    var d = new Date(it.at);
    $('vM').textContent = [it.project, d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) + ' ' + ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2),
      receiptStatus(it)].join('  ·  ') + (it.kind === 'clip' && !it.blob ? '  ·  original no longer on this phone' : '');
    $('vM').classList.toggle('wait', !it.sent);
    $('viT').textContent = it.name.replace(/\.[^.]+$/, '');
    $('viM').textContent = [it.kind === 'clip' ? 'Clip' : it.kind === 'gif' ? 'GIF' : 'Still', d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }), receiptStatus(it)].join(' · ');
    $('viP').textContent = it.project;
    $('viTags').innerHTML = (it.tags || []).map(function (t) { return '<span class="chip">#' + esc(t) + '</span>'; }).join('');
    $('view').classList.add('on'); $('view').classList.remove('bare');
    document.body.classList.add('viewing');
  }
  function closeView() { var v = $('vPic').querySelector('video'); if (v) v.pause(); $('view').classList.remove('on', 'info'); document.body.classList.remove('viewing'); }
  $('feed').addEventListener('click', function (e) { var b = e.target.closest('.shot'); if (b) { vsrc = listNow; openView(+b.dataset.i); } });
  $('vM').addEventListener('click', function () { $('view').classList.add('info'); });
  $('viMove').addEventListener('click', function () { $('vMove').click(); });
  $('viShare').addEventListener('click', function () { $('vShare').click(); });
  $('viDel').addEventListener('click', function () { $('vDel').click(); });
  $('vBack').addEventListener('click', closeView);
  $('vDel').addEventListener('click', function () {
    var it = vlist()[vi]; if (!it) return;
    if (!confirm(it.received ? 'Delete this phone’s copy? The Mac previously confirmed receipt; check that you still have its original.' : 'Delete it? It hasn’t gone to your Mac yet.')) return;
    drop(it.id).then(function () { return refresh(); }).then(function () { var n = vlist().length; $('view').classList.remove('info'); if (n) openView(Math.min(vi, n - 1)); else closeView(); });
  });
  $('vMove').addEventListener('click', function () { var it = vlist()[vi]; if (!it) return; moving = it; drawProjects(); $('newProj').value = ''; sheet('projSheet', true); });
  $('vShare').addEventListener('click', function () {
    var it = vlist()[vi]; if (!it || !navigator.share) return;
    var f = it.blob ? new File([it.blob], it.name, { type: it.type || it.blob.type }) : it.pv ? new File([it.pv], it.name.replace(/\.[^.]+$/, '') + '.jpg', { type: 'image/jpeg' }) : null;
    if (!f) return;
    if (!it.blob) toast('Sharing the preview only — check Photos or your Mac for the original');
    navigator.share({ files: [f] }).catch(function () {});
  });
  // Tap: the picture alone. Swipe sideways: the next. Swipe down: back to the feed.
  var t0 = null, lastTouch = 0;
  $('view').addEventListener('touchstart', function (e) { if (e.target.closest('button, video')) { t0 = null; return; } t0 = { x: e.touches[0].clientX, y: e.touches[0].clientY, at: Date.now() }; }, { passive: true });
  $('view').addEventListener('touchend', function (e) {
    lastTouch = Date.now();
    if (!t0) return;
    var dx = e.changedTouches[0].clientX - t0.x, dy = e.changedTouches[0].clientY - t0.y, quick = Date.now() - t0.at < 300; t0 = null;
    var info = $('view').classList.contains('info');
    if (dy < -60 && Math.abs(dy) > Math.abs(dx)) return $('view').classList.add('info');
    if (dy > 90 && Math.abs(dy) > Math.abs(dx)) return info ? $('view').classList.remove('info') : closeView();
    if (info) return;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) return openView(vi + (dx < 0 ? 1 : -1));
    if (quick && Math.abs(dx) < 8 && Math.abs(dy) < 8) $('view').classList.toggle('bare');
  });
  $('vStage').addEventListener('click', function () { if (Date.now() - lastTouch > 600) $('view').classList.toggle('bare'); });
  addEventListener('keydown', function (e) {
    if (!$('view').classList.contains('on')) return;
    if (e.key === 'Escape') { if ($('view').classList.contains('info')) $('view').classList.remove('info'); else closeView(); } else if (e.key === 'ArrowRight') openView(vi + 1); else if (e.key === 'ArrowLeft') openView(vi - 1);
  });

  /* ---- pairing: scan the code on your Mac — your project names come across, nothing else */
  var scan = { stream: null, t: 0, busy: false };
  function loadJsQR() {
    if (window.jsQR) return Promise.resolve();
    return new Promise(function (ok, no) { var sc = document.createElement('script'); sc.src = '/capture/jsQR.js'; sc.onload = ok; sc.onerror = function () { no(new Error('The code reader didn’t load — check your signal and try again')); }; document.head.appendChild(sc); });
  }
  function pairStat(t, bad) { $('pairStat').textContent = t; $('pairStat').classList.toggle('bad', !!bad); }
  function openPair() { sheet(null, false); pull().then(function (ok) { if (ok) toast('Projects updated from ' + MAC); }); }
  function stopScan() { clearTimeout(scan.t); if (scan.stream) scan.stream.getTracks().forEach(function (t) { t.stop(); }); scan.stream = null; $('pairVid').srcObject = null; }
  var qc = null;
  function tick() {
    var v = $('pairVid');
    if (!scan.stream) return;
    if (v.readyState >= 2 && v.videoWidth) {
      var w = Math.min(640, v.videoWidth), h = Math.round(w * v.videoHeight / v.videoWidth);
      qc = qc || document.createElement('canvas'); qc.width = w; qc.height = h;
      var x = qc.getContext('2d', { willReadFrequently: true }); x.drawImage(v, 0, 0, w, h);
      var code = window.jsQR(x.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: 'attemptBoth' });
      if (code && code.data) return found(code.data);
    }
    scan.t = setTimeout(tick, 160);
  }
  function found(text) {
    var q = null; try { q = new URL(text, location.href).searchParams; } catch (e) {}
    var list = q ? fromLink(q) : [];
    if (!list.length) { pairStat('That’s not the code from Needed Tools — Home › Your phone', true); scan.t = setTimeout(tick, 900); return; }
    stopScan();
    if (navigator.vibrate) navigator.vibrate(30);
    try { takeKey(new URL(text, location.href).hash); } catch (e) {}
    showPaired(takeMac(list, q.get('m') || ''));
  }
  function showPaired(fresh) {
    MAC = get('mac', 'your Mac');
    var list = get('macProjects', []);
    $('pairH').textContent = 'Paired with ' + MAC;
    $('pairN').textContent = list.length + ' project' + (list.length === 1 ? '' : 's') + ' · up to date just now';
    $('pairDone').querySelector('p').textContent = get('pairKey', '') ? 'New projects on your Mac come across by themselves — whenever this opens, or you Sync.' : 'Made a new project on your Mac? Scan again and it comes across.';
    var ordered = fresh.concat(list.filter(function (p) { return fresh.indexOf(p) < 0; }));
    $('pairList').innerHTML = ordered.slice(0, 8).map(function (p) { var n = S.items.filter(function (it) { return it.project === p; }).length; return '<div>' + esc(p) + (fresh.indexOf(p) >= 0 ? '<b>NEW</b>' : '') + '<small>' + (n ? n + ' here' : '—') + '</small></div>'; }).join('')
      + (ordered.length > 8 ? '<div style="font-size:13px;color:var(--soft)">+ ' + (ordered.length - 8) + ' more</div>' : '');
    $('pairScan').classList.add('off'); $('pairDone').classList.remove('off');
    if (!S.project && list[0]) { S.project = list[0]; put('project', S.project); }
    draw();
  }
  function closePair() { stopScan(); $('pair').classList.remove('on'); draw(); }
  $('pairX').addEventListener('click', closePair);
  $('pairGo').addEventListener('click', function () { closePair(); S.view = 'projects'; put('view', 'projects'); draw(); });
  $('pairType').addEventListener('click', function () { closePair(); moving = null; drawProjects(); $('newProj').value = ''; sheet('projSheet', true); setTimeout(function () { $('newProj').focus(); }, 350); });
  $('mPair').addEventListener('click', openPair);

  /* ---- filters */
  $('chips').addEventListener('click', function (e) { var b = e.target.closest('[data-k]'); if (b) { S.kind = b.dataset.k; draw(); } });
  $('searchBtn').addEventListener('click', function () { var s = $('search'); var on = s.style.display !== 'block'; s.style.display = on ? 'block' : 'none'; if (on) $('q').focus(); else { $('q').value = ''; S.q = ''; drawFeed(); } });
  $('q').addEventListener('input', function () { S.q = $('q').value; drawFeed(); });
  $('viewSeg').addEventListener('click', function (e) { var b = e.target.closest('[data-v]'); if (!b) return; S.view = b.dataset.v; put('view', S.view); scrollTo(0, 0); draw(); });
  $('onlyBack').addEventListener('click', function () { S.only = ''; S.kind = 'all'; draw(); });
  $('projBox').addEventListener('click', function (e) {
    if (e.target.closest('#plUpdate')) return openPair();
    var h = e.target.closest('[data-only]'); if (h) { S.only = h.dataset.only; S.kind = 'all'; scrollTo(0, 0); return draw(); }
    var b = e.target.closest('[data-pv]'); if (b) { var p = b.dataset.pv; vsrc = function () { return S.items.filter(function (it) { return it.project === p; }); }; openView(+b.dataset.i); }
  });
  $('capture').addEventListener('click', function (e) {
    var c = e.target.closest('[data-gg]'); if (c) { S.grabGo = S.project = c.dataset.gg; put('grabGo', S.grabGo); put('project', S.project); return draw(); }
    var k = e.target.closest('[data-cap]'); if (k) { var p = S.grabGo, today = new Date().toDateString(); vsrc = function () { return S.items.filter(function (it) { return it.project === p && new Date(it.at).toDateString() === today; }); }; openView(+k.dataset.cap); }
  });
  $('bigShot').addEventListener('click', function () { $('shoot').click(); });
  $('capPhotos').addEventListener('click', function () { $('pick').click(); });

  // This page is served by the Mac. Its IndexedDB queue survives interrupted transfers,
  // but loading the page again requires the Mac to be reachable (HTTP has no service worker).
  if (S.project) keepProject(S.project);
  showInstall(false);
  $('mHomeRow').style.display = 'none';
  $('mPair').textContent = 'Refresh from Mac';
  addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible' && db) pull().then(function (ok) { if (ok) resumeDirect(); }); });
  addEventListener('online', function () { if (db) pull().then(function (ok) { if (ok) resumeDirect(); }); });
  open().then(refresh).then(pull).then(function (ok) { if (ok) resumeDirect(); }).catch(function (e) { toast('This browser can’t keep files here: ' + (e && e.message || e), 6000); draw(); });
  window.__nv = { S: S, refresh: refresh };
  window.__nvReady = true;
})();
