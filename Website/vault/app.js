/* Needed Vault — on the phone, anywhere (Round 21).
   Everything you add stays on this phone (IndexedDB) until you send it to your Mac.
   Send to Mac shares the files — AirDrop them to your Mac — each named
       NV ~ Lexus ~ night, car ~ IMG_1234.jpg
   so Needed Tools knows where each goes when you press Sync. Nothing is uploaded
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
  var S = { project: get('project', '') || fromMac[0] || '', kind: 'all', q: '', grabGo: get('grabGo', ''), items: [] };

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
    return all().then(function (list) { list.sort(function (a, b) { return b.at - a.at; }); S.items = list; draw(); });
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

  /* ---- drawing */
  function kindOf(type, name) {
    if (/gif$/i.test(type) || /\.gif$/i.test(name)) return 'gif';
    if (/^video\//.test(type) || /\.(mov|mp4|m4v)$/i.test(name)) return 'clip';
    return 'still';
  }
  function waiting() { return S.items.filter(function (it) { return !it.sent; }); }
  function listNow() {
    var s = S.q.trim().toLowerCase();
    return S.items.filter(function (it) {
      if (it.project !== S.project) return false;
      if (S.kind !== 'all' && it.kind !== S.kind) return false;
      return !s || (it.name + ' ' + (it.tags || []).join(' ')).toLowerCase().indexOf(s) >= 0;
    });
  }
  var urls = {};
  function thumbURL(it) { if (!it.thumb) return ''; return it.thumb; }
  function drawGrid() {
    var list = listNow(), w = Math.min(innerWidth, 560) - 28, rows = [], row = [], sum = 0, target = 118;
    list.forEach(function (it, i) { var a = Math.min(3, Math.max(0.4, it.a || 1.4)); row.push([it, a, i]); sum += a; if (sum * target + (row.length - 1) * 5 >= w) { rows.push([row, sum]); row = []; sum = 0; } });
    if (row.length) rows.push([row, Math.max(sum, w / target * 0.75)]);
    $('grid').innerHTML = list.length ? rows.map(function (r) {
      var h = Math.round((w - (r[0].length - 1) * 5) / r[1]);
      return '<div class="row">' + r[0].map(function (c) {
        var it = c[0], th = thumbURL(it);
        return '<button class="tile" data-i="' + c[2] + '" style="flex:' + c[1] + ' 1 0;height:' + h + 'px">' + (th ? '<img alt="" src="' + th + '">' : '')
          + (it.kind !== 'still' ? '<span class="badge">' + (it.kind === 'clip' ? 'CLIP' : 'GIF') + '</span>' : '')
          + (it.sent ? '<span class="badge sent">ON MAC</span>' : '<span class="badge new">WAITING</span>') + '</button>';
      }).join('') + '</div>';
    }).join('') : '<div class="empty">' + (S.project ? 'Nothing in ' + esc(S.project) + ' on this phone yet — Photos or Camera below adds some. It all stays here until you send it to your Mac.' : 'Pick a project up top — or make one — then add photos and clips.') + '</div>';
  }
  function drawFeed() {
    var today = new Date().toDateString(), list = S.items.filter(function (it) { return it.project === S.grabGo && new Date(it.at).toDateString() === today; });
    $('todayN').textContent = 'Today, ' + list.length + ' added';
    $('feed').innerHTML = list.length ? list.slice(0, 40).map(function (it) {
      var t = new Date(it.at), hm = ('0' + t.getHours()).slice(-2) + ':' + ('0' + t.getMinutes()).slice(-2);
      return '<div class="it"><span class="th" style="' + (it.thumb ? 'background-image:url(' + it.thumb + ')' : '') + '"></span><span class="tx"><span>' + (it.kind === 'clip' ? 'Clip' : it.kind === 'gif' ? 'GIF' : 'Photo') + ' ' + hm + '</span><span>' + esc((it.tags || []).map(function (x) { return '#' + x; }).join(' ')) + '</span></span><span class="st' + (it.sent ? '' : ' wait') + '">' + (it.sent ? 'On your Mac' : 'Waiting') + '</span></div>';
    }).join('') : '<div class="empty" style="padding:18px 0">Nothing yet today.</div>';
  }
  function drawSend() {
    var w = waiting(), n = w.length;
    $('sendBar').classList.toggle('off', !n);
    if (!n) return;
    var ps = []; w.forEach(function (it) { if (ps.indexOf(it.project) < 0) ps.push(it.project); });
    $('sendN').textContent = n + ' waiting for ' + MAC;
    $('sendWhere').textContent = ps.length === 1 ? 'All for ' + ps[0] : ps.length + ' projects';
    $('sendGo').textContent = n > BATCH ? 'Send ' + BATCH + ' to Mac' : 'Send to Mac';
  }
  function draw() {
    var on = !!S.grabGo;
    $('pillName').textContent = (on ? S.grabGo : S.project) || 'Projects';
    $('gg').classList.toggle('on', on); $('gg').setAttribute('aria-pressed', on); $('ggWrap').classList.toggle('on', on);
    $('browse').classList.toggle('off', on); $('on').classList.toggle('off', !on);
    $('title').textContent = S.project || 'Needed Vault';
    var mine = S.items.filter(function (it) { return it.project === S.project; });
    $('count').textContent = mine.length ? mine.length + ' on this phone' : '';
    [].forEach.call(document.querySelectorAll('#chips [data-k]'), function (b) { b.classList.toggle('on', b.dataset.k === S.kind); });
    if (on) { $('onLine').textContent = 'Everything goes straight into ' + S.grabGo + '. No questions until you switch it off.'; drawFeed(); } else drawGrid();
    drawSend();
  }

  /* ---- sheets */
  var SHEETS = ['projSheet', 'addSheet', 'menuSheet', 'sendSheet'];
  function sheet(id, open) {
    SHEETS.forEach(function (s) { $(s).classList.toggle('on', open && s === id); });
    $('veil').classList.toggle('on', !!open);
  }
  $('veil').addEventListener('click', function () { sheet(null, false); pending = []; });

  /* ---- projects */
  function drawProjects() {
    var ps = projects();
    $('plist').innerHTML = ps.map(function (p) {
      var n = S.items.filter(function (it) { return it.project === p; }).length;
      return '<button class="' + (p === (S.grabGo || S.project) ? 'on' : '') + '" data-p="' + esc(p) + '">' + esc(p) + '<small>' + (n ? n + ' here' : '') + '</small></button>';
    }).join('') || '<div class="empty" style="padding:14px 0">No projects yet. Scan the QR code in Needed Tools › Your phone to bring yours across — or type one below.</div>';
  }
  $('pill').addEventListener('click', function () { drawProjects(); $('newProj').value = ''; sheet('projSheet', true); });
  function pickProject(p) {
    S.project = p; put('project', p); keepProject(p);
    if (S.grabGo) { S.grabGo = p; put('grabGo', p); }
    S.kind = 'all'; S.q = ''; $('q').value = ''; draw();
  }
  $('plist').addEventListener('click', function (e) { var b = e.target.closest('[data-p]'); if (!b) return; sheet(null, false); pickProject(b.dataset.p); });
  function cleanName(s) { return String(s || '').replace(/[~\/:|#]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80); }
  $('newProjGo').addEventListener('click', function () {
    var p = cleanName($('newProj').value); if (!p) return $('newProj').focus();
    sheet(null, false); pickProject(p); toast('New project — ' + p);
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
  $('bigTap').addEventListener('click', function () { $('pick').click(); });
  $('camera').addEventListener('click', function () { $('shoot').click(); });
  $('camera2').addEventListener('click', function () { $('shoot').click(); });
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
  function thumbOf(f) {
    if (/^video\//.test(f.type)) return videoThumb(f);
    if (!window.createImageBitmap) return Promise.resolve({ th: '', a: 1.4 });
    return createImageBitmap(f).then(function (b) { return shrink(b, b.width, b.height); }).catch(function () { return { th: '', a: 1.4 }; });
  }
  function shrink(src, w, h) {
    var c = document.createElement('canvas'), s = 360 / Math.max(w, h); c.width = Math.max(1, Math.round(w * s)); c.height = Math.max(1, Math.round(h * s));
    c.getContext('2d').drawImage(src, 0, 0, c.width, c.height);
    return { th: c.toDataURL('image/jpeg', 0.72), a: w / h };
  }
  function videoThumb(f) {
    return new Promise(function (ok) {
      var v = document.createElement('video'), u = URL.createObjectURL(f), done = false;
      var fin = function (r) { if (done) return; done = true; URL.revokeObjectURL(u); ok(r); };
      v.muted = true; v.playsInline = true; v.preload = 'metadata'; v.src = u;
      v.onloadeddata = function () { try { v.currentTime = Math.min(0.5, (v.duration || 1) / 3); } catch (e) { fin({ th: '', a: 1.78 }); } };
      v.onseeked = function () { try { fin(shrink(v, v.videoWidth, v.videoHeight)); } catch (e) { fin({ th: '', a: 1.78 }); } };
      v.onerror = function () { fin({ th: '', a: 1.78 }); };
      setTimeout(function () { fin({ th: '', a: 1.78 }); }, 4000);
    });
  }
  function keep(files, project, tags) {
    var i = 0, n = files.length;
    $('prog').classList.add('on'); $('progBar').style.width = '0%';
    function next() {
      if (i >= n) return Promise.resolve();
      var f = files[i];
      return thumbOf(f).then(function (t) {
        var it = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 7), blob: f, type: f.type || '', name: stampName(f), kind: kindOf(f.type || '', f.name || ''),
                   project: project, tags: tags, at: Date.now(), sent: 0, thumb: t.th, a: t.a, bytes: f.size };
        return save(it);
      }).then(function () { i++; $('progBar').style.width = Math.round(i / n * 100) + '%'; return next(); });
    }
    next().then(function () {
      $('prog').classList.remove('on');
      if (project !== S.project && !S.grabGo) { S.project = project; put('project', project); }
      toast((n === 1 ? 'Kept for ' : n + ' kept for ') + project + ' — send when you’re back at your Mac');
      refresh();
    }).catch(function (e) {
      $('prog').classList.remove('on');
      toast(/quota/i.test(String(e && e.name)) ? 'This phone’s out of room for Needed Vault — send some to your Mac first' : 'Couldn’t keep that one: ' + (e && e.message || e), 4200);
      refresh();
    });
  }

  /* ---- Send to Mac: the share sheet → AirDrop → Downloads → Sync files them */
  var BATCH = 25;
  function shareName(it, used) {
    var tags = (it.tags || []).join(', ') || '-';
    var name = 'NV ~ ' + cleanName(it.project) + ' ~ ' + tags + ' ~ ' + it.name;
    var n = 2, base = name.replace(/\.[^.]+$/, ''), ext = name.split('.').pop();
    while (used[name]) { name = base + ' ' + n + '.' + ext; n++; }
    used[name] = 1;
    return name;
  }
  $('sendGo').addEventListener('click', function () {
    var w = waiting().slice().reverse().slice(0, BATCH);     // oldest first
    if (!w.length) return;
    if (!navigator.share || !window.File) return sheet('sendSheet', true);
    var used = {}, files = w.map(function (it) { return new File([it.blob], shareName(it, used), { type: it.type || it.blob.type || 'application/octet-stream' }); });
    if (navigator.canShare && !navigator.canShare({ files: files })) return sheet('sendSheet', true);
    navigator.share({ files: files }).then(function () {
      var at = Date.now();
      return Promise.all(w.map(function (it) { it.sent = at; return save(it); }));
    }).then(function () {
      var left = waiting().length - w.length;
      toast(left > 0 ? w.length + ' sent — ' + left + ' more to go' : 'Sent — now press Sync on your Mac', 4200);
      refresh();
    }).catch(function (e) {
      if (e && e.name === 'AbortError') return;                    // closed the share sheet
      toast('Couldn’t send those — try fewer at once', 4200);
    });
  });
  $('sendHow').addEventListener('click', function () { sheet('sendSheet', true); });
  $('sendOk').addEventListener('click', function () { sheet(null, false); });

  /* ---- the menu: how it works, room on the phone, make it an app */
  $('mark').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.sent; }), bytes = sent.reduce(function (a, it) { return a + (it.bytes || 0); }, 0);
    $('mSent').textContent = sent.length ? sent.length + ' already on your Mac · ' + (bytes / 1048576).toFixed(bytes > 1048576 * 10 ? 0 : 1) + ' MB' : 'Nothing to clear';
    $('mClear').disabled = !sent.length;
    $('mMac').textContent = MAC;
    $('mHomeRow').classList.toggle('off', APP);
    sheet('menuSheet', true);
  });
  $('mClear').addEventListener('click', function () {
    var sent = S.items.filter(function (it) { return it.sent; });
    if (!sent.length || !confirm('Take the ' + sent.length + ' already sent off this phone? They stay safe in your vault on the Mac.')) return;
    Promise.all(sent.map(function (it) { return drop(it.id); })).then(function () { sheet(null, false); toast('Room made on this phone'); refresh(); });
  });
  $('mHome').addEventListener('click', function () { sheet(null, false); showInstall(true); });
  $('mDone').addEventListener('click', function () { sheet(null, false); });

  /* ---- one picture */
  var vi = -1, vurl = '';
  function openView(i) {
    var list = listNow(), it = list[i]; if (!it) return; vi = i;
    if (vurl) URL.revokeObjectURL(vurl);
    vurl = URL.createObjectURL(it.blob);
    $('vBack').textContent = '‹ ' + (S.project || 'Back'); $('vN').textContent = (i + 1) + ' / ' + list.length;
    $('vPic').innerHTML = it.kind === 'clip' ? '<video src="' + vurl + '" controls playsinline preload="metadata"></video>' : '<img alt="" src="' + vurl + '">';
    $('vT').textContent = it.name.replace(/\.[^.]+$/, '');
    var d = new Date(it.at);
    $('vM').textContent = [it.kind === 'clip' ? 'Clip' : it.kind === 'gif' ? 'GIF' : 'Still', 'added ' + d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }), it.sent ? 'on your Mac' : 'waiting for your Mac'].join(' · ');
    $('vTags').innerHTML = (it.tags || []).map(function (t) { return '<span class="chip">#' + esc(t) + '</span>'; }).join('');
    $('view').classList.add('on');
  }
  function closeView() { var v = $('vPic').querySelector('video'); if (v) v.pause(); $('view').classList.remove('on'); }
  $('grid').addEventListener('click', function (e) { var b = e.target.closest('.tile'); if (b) openView(+b.dataset.i); });
  $('vBack').addEventListener('click', closeView);
  $('vDel').addEventListener('click', function () {
    var it = listNow()[vi]; if (!it) return;
    if (!confirm(it.sent ? 'Take it off this phone? It stays in your vault on the Mac.' : 'Delete it? It hasn’t gone to your Mac yet.')) return;
    drop(it.id).then(function () { closeView(); refresh(); });
  });
  $('vShare').addEventListener('click', function () {
    var it = listNow()[vi]; if (!it || !navigator.share) return;
    var f = new File([it.blob], it.name, { type: it.type || it.blob.type });
    navigator.share({ files: [f] }).catch(function () {});
  });
  var x0 = null;
  $('view').addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; }, { passive: true });
  $('view').addEventListener('touchend', function (e) { if (x0 == null) return; var d = e.changedTouches[0].clientX - x0; x0 = null; if (Math.abs(d) > 50) openView(vi + (d < 0 ? 1 : -1)); });

  /* ---- filters */
  $('chips').addEventListener('click', function (e) { var b = e.target.closest('[data-k]'); if (b) { S.kind = b.dataset.k; draw(); } });
  $('searchBtn').addEventListener('click', function () { var s = $('search'); var on = s.style.display !== 'block'; s.style.display = on ? 'block' : 'none'; if (on) $('q').focus(); else { $('q').value = ''; S.q = ''; drawGrid(); } });
  $('q').addEventListener('input', function () { S.q = $('q').value; drawGrid(); });
  addEventListener('resize', function () { if (!S.grabGo) drawGrid(); });

  /* ---- offline: the page keeps itself on the phone */
  if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(function () {});

  if (S.project) keepProject(S.project);
  showInstall(false);
  open().then(refresh).catch(function (e) { toast('This browser can’t keep files here: ' + (e && e.message || e), 6000); draw(); });
  window.__nv = { S: S, refresh: refresh };
})();
