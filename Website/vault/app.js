/* Needed Mobile Vault — on the phone, anywhere (Round 21).
   Everything you add stays on this phone (IndexedDB) until you send it to your Mac.
   Sync shares the files — Save to Photos (iCloud Photos takes them to your Mac), or
   AirDrop — each named
       NV ~ Lexus ~ night, car ~ IMG_1234 ~ k3f9x2a.jpg
   so Needed Tools knows where each goes when you press Sync there. The last part is
   this phone's id for it: however many times it's sent, the vault files it once. Nothing is uploaded
   to the website: it only hands over this page, once, and then it works offline. */
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
  var params = new URLSearchParams(location.search);
  var fromMac = (params.get('p') || '').split('|').map(function (s) { return s.trim(); }).filter(Boolean);
  if (params.get('m')) put('mac', params.get('m'));
  var MAC = get('mac', 'your Mac');
  function projects() {
    var mine = get('projects', []), all = [];
    fromMac.concat(mine).forEach(function (p) { if (p && all.indexOf(p) < 0) all.push(p); });
    return all;
  }
  function keepProject(p) { var mine = get('projects', []); if (mine.indexOf(p) < 0 && fromMac.indexOf(p) < 0) { mine.unshift(p); put('projects', mine.slice(0, 60)); } }
  var S = { project: get('project', '') || fromMac[0] || '', kind: 'all', q: '', grabGo: get('grabGo', ''), scope: get('scope', 'all'), items: [] };

  /* ---- the phone's own store */
  var db = null;
  function open() {
    return new Promise(function (ok, no) {
      if (!window.indexedDB) return no(new Error('This browser can’t keep files'));
      var r = indexedDB.open('needed-vault', 1);
      r.onupgradeneeded = function () { var s = r.result.createObjectStore('items', { keyPath: 'id' }); s.createIndex('at', 'at'); };
      r.onsuccess = function () { db = r.result; ok(db); };
      r.onerror = function () { no(r.error); };
    });
  }
  function tx(mode) { return db.transaction('items', mode).objectStore('items'); }
  function all() { return new Promise(function (ok, no) { var r = tx('readonly').getAll(); r.onsuccess = function () { ok(r.result || []); }; r.onerror = function () { no(r.error); }; }); }
  function save(it) { return new Promise(function (ok, no) { var r = tx('readwrite').put(it); r.onsuccess = function () { ok(it); }; r.onerror = function () { no(r.error); }; }); }
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
    var need = force || (!APP && !get('skipInstall', false));
    $('install').classList.toggle('off', !need);
    $('app').classList.toggle('off', need);
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
  function waiting() { return S.items.filter(function (it) { return !it.sent && it.blob; }); }
  function listNow() {
    var s = S.q.trim().toLowerCase();
    return S.items.filter(function (it) {
      if (S.scope !== 'all' && it.project !== S.project) return false;
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
      + (it.sent ? '' : '<span class="dot" title="Not synced yet"></span>') + '</button>';
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
        out += '<div class="run"><div class="runh"><span class="cap">' + esc(r.project) + ' · ' + r.items.length + '</span>' + (w ? '<span class="cap wait">' + w + ' not synced</span>' : '') + '</div>' + group(r.items, r.idx) + '</div>';
      });
      out += '</section>';
    });
    $('feed').innerHTML = out || '<div class="empty">' + (S.q || S.kind !== 'all' ? 'Nothing matches.'
      : S.project ? 'Nothing here yet. <b>Photos</b> or <b>Camera</b> below — it waits on this phone until you Sync it to your Mac.' : 'Pick a project up top — or make one — then add photos and clips.') + '</div>';
  }
  function drawSend() {
    var w = waiting(), n = w.length;
    $('sendBar').classList.toggle('off', !n);
    if (!n) return;
    var ps = []; w.forEach(function (it) { if (ps.indexOf(it.project) < 0) ps.push(it.project); });
    $('sendN').textContent = n + ' not synced yet';
    $('sendWhere').textContent = ps.length === 1 ? 'All for ' + ps[0] : ps.length + ' projects';
    $('sendGo').textContent = n > BATCH ? 'Sync ' + BATCH : 'Sync';
  }
  function draw() {
    var on = !!S.grabGo;
    $('pillName').textContent = (on ? S.grabGo : S.project) || 'Projects';
    $('gg').classList.toggle('on', on); $('gg').setAttribute('aria-pressed', on); $('ggWrap').classList.toggle('on', on);
    $('ggLine').classList.toggle('off', !on);
    $('ggLine').textContent = on ? 'Grab & Go — everything goes straight into ' + S.grabGo : '';
    $('title').textContent = S.scope === 'all' ? 'Your grabs' : (S.project || 'Your grabs');
    [].forEach.call(document.querySelectorAll('#scope [data-s]'), function (b) { b.classList.toggle('on', b.dataset.s === S.scope); });
    $('scopeP').textContent = S.project || 'Project';
    var mine = S.items.filter(function (it) { return S.scope === 'all' || it.project === S.project; });
    $('count').textContent = mine.length ? mine.length + ' on this phone' : '';
    [].forEach.call(document.querySelectorAll('#chips [data-k]'), function (b) { b.classList.toggle('on', b.dataset.k === S.kind); });
    drawFeed();
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
    var ps = projects();
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
    save(it).then(function () { toast(it.sent ? 'Moved to ' + p + ' here — on your Mac it stays where it was filed' : 'Moved to ' + p); refresh().then(function () { var k = listNow().indexOf(S.items.filter(function (x) { return x.id === it.id; })[0]); if (k >= 0) openView(k); else closeView(); }); });
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
    addTo = S.project; drawAddProjects(); $('addTags').value = ''; $('addNew').value = '';
    sheet('addSheet', true);
  }
  $('pick').addEventListener('change', picked);
  $('shoot').addEventListener('change', picked);
  function drawAddProjects() {
    $('addProjects').innerHTML = projects().map(function (p) { return '<button class="chip' + (p === addTo ? ' on' : '') + '" data-to="' + esc(p) + '">' + esc(p) + '</button>'; }).join('');
    $('addGo').textContent = addTo ? 'Keep for ' + addTo : 'Pick a project';
    $('addGo').disabled = !addTo;
  }
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
  // Once a grab has been synced a day, the full file goes and the preview stays — the original is on your Mac.
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
  // In the background: a preview for anything without one; full files a day after Sync go, the preview stays.
  var DAY = 86400000, tidying = false;
  function tidy() {
    if (tidying || !db) return;
    var todo = S.items.filter(function (it) { return (!it.pv && it.blob) || (it.blob && it.sent && Date.now() - it.sent > DAY); });
    if (!todo.length) return;
    tidying = true;
    var k = 0, changed = false;
    (function next() {
      if (k >= todo.length) { tidying = false; if (changed) refresh(); return; }
      var it = todo[k++];
      (it.pv ? Promise.resolve(null) : thumbOf(it.blob)).then(function (t) {
        if (t && t.pv) { it.pv = t.pv; it.a = t.a || it.a; it.thumb = ''; }
        if (it.pv && it.sent && Date.now() - it.sent > DAY) { it.blob = null; it.slim = 1; }
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
      toast((n === 1 ? 'Kept for ' : n + ' kept for ') + project + ' — Sync when you’re ready');
      refresh();
    }).catch(function (e) {
      $('prog').classList.remove('on');
      toast(/quota/i.test(String(e && e.name)) ? 'This phone’s out of room for Mobile Vault — send some to your Mac first' : 'Couldn’t keep that one: ' + (e && e.message || e), 4200);
      refresh();
    });
  }

  /* ---- Sync: the share sheet → Save to Photos (iCloud → your Mac) or AirDrop → Sync on the Mac files them */
  var BATCH = 25;
  function shareName(it) {
    var tags = (it.tags || []).map(cleanName).join(', ') || '-';
    var stem = it.name.replace(/\.[^.]+$/, ''), ext = (it.name.match(/\.([^.]+)$/) || [0, 'jpg'])[1];
    return 'NV ~ ' + cleanName(it.project) + ' ~ ' + tags + ' ~ ' + cleanName(stem) + ' ~ ' + it.id + '.' + ext;
  }
  function syncItems(w) {
    if (!w.length) return;
    if (!navigator.share || !window.File) return sheet('sendSheet', true);
    var files = w.map(function (it) { return new File([it.blob], shareName(it), { type: it.type || it.blob.type || 'application/octet-stream' }); });
    if (navigator.canShare && !navigator.canShare({ files: files })) return sheet('sendSheet', true);
    navigator.share({ files: files }).then(function () {
      var at = Date.now();
      return Promise.all(w.map(function (it) { it.sent = at; return save(it); }));
    }).then(function () {
      return refresh();
    }).then(function () {
      var left = waiting().length;
      $('nudgeN').textContent = left > 0 ? w.length + ' synced — ' + left + ' more to go. Sync again for the next ' + Math.min(BATCH, left) + '.' : '';
      sheet('nudgeSheet', true);                                   // give iCloud its nudge
    }).catch(function (e) {
      if (e && e.name === 'AbortError') return;                    // closed the share sheet
      toast('Couldn’t sync those — try fewer at once', 4200);
    });
  }
  $('sendGo').addEventListener('click', function () { syncItems(waiting().slice().reverse().slice(0, BATCH)); });   // oldest first
  // Opening Photos is what nudges iCloud to send them up now.
  $('nudgePhotos').addEventListener('click', function () { sheet(null, false); location.href = 'photos-redirect://'; });
  $('nudgeDone').addEventListener('click', function () { sheet(null, false); });
  // Can't find something on the Mac? Send the last week again — the vault still files each one once.
  $('mResync').addEventListener('click', function () {
    var week = Date.now() - 7 * 86400000, list = S.items.filter(function (it) { return it.at > week && it.blob; }).reverse().slice(0, BATCH);
    if (!list.length) return toast('Nothing from the last week still here in full — it’s all on your Mac');
    sheet(null, false); syncItems(list);
  });
  $('sendHow').addEventListener('click', function () { sheet('sendSheet', true); });
  $('sendOk').addEventListener('click', function () { sheet(null, false); });

  /* ---- the menu: how it works, room on the phone, make it an app */
  $('mark').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.sent; }), bytes = S.items.reduce(function (a, it) { return a + (it.blob ? it.blob.size || it.bytes || 0 : 0) + (it.pv ? it.pv.size || 0 : 0); }, 0);
    $('mSent').textContent = S.items.length + ' here · ' + (bytes / 1048576).toFixed(bytes > 1048576 * 10 ? 0 : 1) + ' MB';
    $('mClear').disabled = !sent.length;
    $('mMac').textContent = MAC;
    $('mHomeRow').classList.toggle('off', APP);
    sheet('menuSheet', true);
  });
  $('mClear').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.sent; });
    if (!sent.length || !confirm('Take the ' + sent.length + ' already synced out of the feed? They stay in your vault on the Mac.')) return;
    Promise.all(sent.map(function (it) { return drop(it.id); })).then(function () { sheet(null, false); toast('Room made on this phone'); refresh(); });
  });
  $('mHome').addEventListener('click', function () { sheet(null, false); showInstall(true); });
  $('mDone').addEventListener('click', function () { sheet(null, false); });

  /* ---- one picture: light, the picture as big as it goes, the rest out of its way */
  var vi = -1, vurl = '';
  function openView(i) {
    var list = listNow(), it = list[i]; if (!it) return; vi = i;
    var v = $('vPic').querySelector('video'); if (v) v.pause();
    if (vurl) { URL.revokeObjectURL(vurl); vurl = ''; }
    var full = it.blob && (it.kind !== 'still' || !it.pv || it.blob.size < 6e6);     // stills show the preview; clips and GIFs play while they're here
    var src = full ? (vurl = URL.createObjectURL(it.blob)) : picURL(it);
    $('vN').textContent = (i + 1) + ' / ' + list.length;
    $('vPic').innerHTML = it.kind === 'clip' && it.blob ? '<video src="' + src + '" controls playsinline preload="metadata"' + (it.pv ? ' poster="' + esc(picURL(it)) + '"' : '') + '></video>'
      : (src ? '<img alt="" src="' + esc(src) + '">' : '');
    var d = new Date(it.at);
    $('vM').textContent = [it.project, d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) + ' ' + ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2),
      it.sent ? (it.blob ? 'synced' : 'on your Mac') : 'not synced yet'].join('  ·  ') + (it.kind === 'clip' && !it.blob ? '  ·  the clip is on your Mac' : '');
    $('vM').classList.toggle('wait', !it.sent);
    $('view').classList.add('on'); $('view').classList.remove('bare');
    document.body.classList.add('viewing');
  }
  function closeView() { var v = $('vPic').querySelector('video'); if (v) v.pause(); $('view').classList.remove('on'); document.body.classList.remove('viewing'); }
  $('feed').addEventListener('click', function (e) { var b = e.target.closest('.shot'); if (b) openView(+b.dataset.i); });
  $('vBack').addEventListener('click', closeView);
  $('vDel').addEventListener('click', function () {
    var it = listNow()[vi]; if (!it) return;
    if (!confirm(it.sent ? 'Take it off this phone? It stays in your vault on the Mac.' : 'Delete it? It hasn’t gone to your Mac yet.')) return;
    drop(it.id).then(function () { return refresh(); }).then(function () { var n = listNow().length; if (n) openView(Math.min(vi, n - 1)); else closeView(); });
  });
  $('vMove').addEventListener('click', function () { var it = listNow()[vi]; if (!it) return; moving = it; drawProjects(); $('newProj').value = ''; sheet('projSheet', true); });
  $('vShare').addEventListener('click', function () {
    var it = listNow()[vi]; if (!it || !navigator.share) return;
    var f = it.blob ? new File([it.blob], it.name, { type: it.type || it.blob.type }) : it.pv ? new File([it.pv], it.name.replace(/\.[^.]+$/, '') + '.jpg', { type: 'image/jpeg' }) : null;
    if (!f) return;
    if (!it.blob) toast('Sharing the preview — the full one is on your Mac');
    navigator.share({ files: [f] }).catch(function () {});
  });
  // Tap: the picture alone. Swipe sideways: the next. Swipe down: back to the feed.
  var t0 = null, lastTouch = 0;
  $('view').addEventListener('touchstart', function (e) { if (e.target.closest('button, video')) { t0 = null; return; } t0 = { x: e.touches[0].clientX, y: e.touches[0].clientY, at: Date.now() }; }, { passive: true });
  $('view').addEventListener('touchend', function (e) {
    lastTouch = Date.now();
    if (!t0) return;
    var dx = e.changedTouches[0].clientX - t0.x, dy = e.changedTouches[0].clientY - t0.y, quick = Date.now() - t0.at < 300; t0 = null;
    if (dy > 90 && Math.abs(dy) > Math.abs(dx)) return closeView();
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) return openView(vi + (dx < 0 ? 1 : -1));
    if (quick && Math.abs(dx) < 8 && Math.abs(dy) < 8) $('view').classList.toggle('bare');
  });
  $('vStage').addEventListener('click', function () { if (Date.now() - lastTouch > 600) $('view').classList.toggle('bare'); });
  addEventListener('keydown', function (e) {
    if (!$('view').classList.contains('on')) return;
    if (e.key === 'Escape') closeView(); else if (e.key === 'ArrowRight') openView(vi + 1); else if (e.key === 'ArrowLeft') openView(vi - 1);
  });

  /* ---- filters */
  $('chips').addEventListener('click', function (e) { var b = e.target.closest('[data-k]'); if (b) { S.kind = b.dataset.k; draw(); } });
  $('searchBtn').addEventListener('click', function () { var s = $('search'); var on = s.style.display !== 'block'; s.style.display = on ? 'block' : 'none'; if (on) $('q').focus(); else { $('q').value = ''; S.q = ''; drawFeed(); } });
  $('q').addEventListener('input', function () { S.q = $('q').value; drawFeed(); });
  $('scope').addEventListener('click', function (e) { var b = e.target.closest('[data-s]'); if (!b) return; S.scope = b.dataset.s; put('scope', S.scope); draw(); });

  /* ---- offline: the page keeps itself on the phone */
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) navigator.serviceWorker.register('/vault/sw.js', { scope: '/vault/' }).catch(function () {});

  if (S.project) keepProject(S.project);
  showInstall(false);
  open().then(refresh).catch(function (e) { toast('This browser can’t keep files here: ' + (e && e.message || e), 6000); draw(); });
  window.__nv = { S: S, refresh: refresh };
  window.__nvReady = true;
})();
