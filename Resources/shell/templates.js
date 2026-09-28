/* Needed Design — treatment templates, second generation.
   Six templates, one professional running order of 15 pages each. Every template is a small type-and-grid
   system (margins, gutter, heading, kicker, body) applied to the same set of page layouts, so pages line up:
   headings sit in the same place on every page, text never sits on a busy picture without a plate under it.
   Pages are drawn on 1920 × 1080 in pixels; the editor turns them into ordinary, editable pages. */
(function () {
  'use strict';
  const W = 1920, H = 1080;
  const P = (x, y, w, h, o) => Object.assign({ k: 'pic', x, y, w, h }, o || {});
  const T = (text, x, y, w, st) => Object.assign({ k: 'text', text, x, y, w }, st || {});
  const S = (shape, x, y, w, h, st) => Object.assign({ k: 'shape', shape, x, y, w, h }, st || {});
  const L = {
    s: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere erat a ante venenatis dapibus posuere velit aliquet.',
    m: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean lacinia bibendum nulla sed consectetur. Maecenas sed diam eget risus varius blandit sit amet non magna. Nullam quis risus eget urna mollis ornare vel eu leo.',
    l: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean lacinia bibendum nulla sed consectetur. Maecenas sed diam eget risus varius blandit sit amet non magna. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Nullam quis risus eget urna mollis ornare vel eu leo. Vivamus sagittis lacus vel augue laoreet rutrum faucibus dolor auctor.',
    note: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. When I first heard the track, nulla vitae elit libero, a pharetra augue. Maecenas faucibus mollis interdum, cras mattis consectetur purus sit amet fermentum.\nDonec ullamcorper nulla non metus auctor fringilla. Vestibulum id ligula porta felis euismod semper, sed posuere consectetur est at lobortis. Aenean eu leo quam, pellentesque ornare sem lacinia quam venenatis vestibulum.\nThis is a film about lorem ipsum — and I want every frame of it to feel earned.',
    idea: 'A quiet portrait of lorem ipsum — told in the moments before everything changes.',
    beats: ['We open on lorem ipsum, alone, in the half-light before the day starts.', 'The world arrives: consectetur adipiscing, noise, movement, pressure.', 'A turn. Sed do eiusmod tempor — the moment everything narrows to one choice.', 'We end where we began, but nothing looks the same. Hold. Cut.'],
    cast: [['Lead', 'Lorem ipsum, late twenties. Still, watchful, unhurried.'], ['Second', 'Dolor sit amet. Warm, restless, the spark in every room.'], ['Supporting', 'Consectetur. The world around them — real faces, not extras.']],
    sched: [['Pre-production', 'Weeks 1–2', 'Casting, scouting, wardrobe, lookbook, shot list'], ['Tech recce', 'Week 3', 'Camera and lighting tests, final locations'], ['Shoot', 'Week 4', 'Two days · one studio, two locations'], ['Post-production', 'Weeks 5–7', 'Edit, grade, sound design, music'], ['Delivery', 'Week 8', 'Hero film, cut-downs, stills, socials']],
  };
  // The biggest size at which the longest word fits a width, for a font about `em` wide per letter.
  const fit = (t, w, max, em) => Math.min(max, Math.floor(w / (Math.max(...String(t).split(/\s+/).map(x => x.length), 1) * em)));
  const lines = (t, w, size, em) => String(t).split('\n').reduce((n, p) => n + Math.max(1, Math.ceil(p.length * size * em / w)), 0);

  // One template: a type-and-grid system.
  function make(s) {
    const P = (x, y, w, h, o) => Object.assign({ k: 'pic', x, y, w, h }, s.picRadius ? { radius: s.picRadius } : {}, s.picBorder ? { border: s.picBorder, bw: s.picBw || 16 } : {}, o || {});
    const M = s.M, TOP = s.top, BOT = H - s.bottom, GAP = s.gut;
    const upper = t => (s.head.upper ? String(t).toUpperCase() : t);
    const kick = (n, label, x, y, w, c) => T((n ? n + (s.kick.sep || '  —  ') : '') + (s.kick.upper === false ? label : String(label).toUpperCase()), x, y, w || 700,
      { font: s.kick.font, size: s.kick.size, weight: s.kick.weight || 500, tracking: s.kick.tracking || 0.16, c: c || s.kick.c || 'accent', role: 'kick' });
    const headSize = (t, w, max) => fit(upper(t), w, max || s.head.size, s.head.em);
    const head = (t, x, y, w, st) => T(upper(t), x, y, w, Object.assign({ font: s.head.font, size: headSize(t, w, (st && st.size) || s.head.size), weight: s.head.weight || 400,
      italic: !!s.head.italic, tracking: s.head.tracking || 0, leading: s.head.leading || 1.05, stretch: s.head.stretch, c: 'ink', role: 'head', fit: true }, st || {}, { size: headSize(t, w, (st && st.size) || s.head.size) }));
    const body = (t, x, y, w, st) => T(t, x, y, w, Object.assign({ font: s.body.font, size: s.body.size, weight: s.body.weight || 400, leading: s.body.leading, align: s.body.align || 'left',
      hyph: s.body.align === 'justify', para: 0.9, c: 'ink', op: s.body.op || 0.9, role: 'body' }, st || {}));
    const rule = (x, y, w, c) => S('line', x, y, w, 2, { fill: c || 'ink', lw: 1, op: s.ruleOp || 0.3 });
    // Kicker, heading, (rule), body — a column that starts at y. Returns the items and where it ends.
    function block(n, label, x, y, w, text, o) {
      o = o || {};
      const it = [kick(n, label, x, y, w, o.kc)];
      let yy = y + s.kick.size * 2.4;
      if (o.title !== false) {
        const t = o.title || label, sz = headSize(t, w, o.hsize), hl = Math.min(3, lines(upper(t), w, sz, s.head.em * 0.86));
        it.push(head(t, x, yy, w, Object.assign({ size: o.hsize || s.head.size }, o.hc ? { c: o.hc } : {})));
        yy += sz * (s.head.leading || 1.05) * hl + s.head.after;
      }
      if (s.rules) { it.push(rule(x, yy - s.head.after / 2, Math.min(w, 120), o.hc)); }
      if (text) it.push(body(text, x, yy, w, o.bc ? { c: o.bc } : {}));
      return it;
    }
    const dark = !!s.dark;
    const onPic = { rc: '#ffffff' };
    // A soft plate that keeps words readable on a picture: from the bottom, the top or one side.
    const plate = (x, y, w, h, from, c, op) => S('rect', x, y, w, h, { fill: c || 'bg', fadeTo: from, fadeAt: 0.25, op: op == null ? 0.92 : op });
    const topShade = () => S('rect', 0, 0, W, 170, { fill: '#000000', fadeTo: 'bottom', fadeAt: 0, op: 0.45 });
    const X0 = s.frame ? M : 0, X1 = s.frame ? W - M : W;           // where pictures run to: the margin, or the edge
    const Y0 = s.frame ? TOP : 0, Y1 = s.frame ? BOT : H;

    const D = {
      cover: c => s.cover(c, { M, TOP, BOT, kick, head, body, rule, plate }),
      note: (c, h, n) => {
        const tx = M, tw = 660, px = s.frame ? 1000 : 960;
        return { items: [...block(n, h, tx, TOP, tw, L.note, { title: s.noteTitle || 'A note from the director' }),
          T('— ' + c.director, tx, BOT - 60, tw, { role: 'sign', font: s.sign.font, size: s.sign.size, italic: !!s.sign.italic, weight: s.sign.weight || 400, c: 'ink' }),
          P(px, Y0, X1 - px, Y1 - Y0, { dim: s.dim })] };
      },
      idea: (c, h, n) => {
        const bw = s.idea.w || 1480, txt = s.idea.upper === false ? L.idea : upper(L.idea);
        const th = lines(txt, bw, s.idea.size, (s.idea.em || s.head.em) * 0.92) * s.idea.size * (s.idea.leading || 1.08), iy = Math.round((H - th) / 2);
        return { items: [kick(n, h, M, iy - 80, 800),
          T(txt, M, iy, bw, { role: 'idea', fit: true, font: s.idea.font || s.head.font, size: s.idea.size, weight: s.idea.weight || s.head.weight || 400, italic: !!s.idea.italic, outline: s.idea.outline || 0,
            leading: s.idea.leading || 1.08, tracking: s.idea.tracking || 0, stretch: s.head.stretch, c: s.idea.c || 'ink' }),
          ...(s.idea.pic ? [P(W - M - 520, BOT - 300, 520, 300, { dim: s.dim })] : [])] };
      },
      beats: (c, h, n) => {
        const fw = (W - 2 * M - 3 * GAP) / 4, fh = Math.round(fw / (s.beatAspect || 1.25)), room = BOT - (TOP + 150), fy = Math.round(TOP + 150 + (room - fh - 150) / 2);
        const it = [...block(n, h, M, TOP, 1000, null)];
        L.beats.forEach((t, i) => {
          const x = M + i * (fw + GAP);
          it.push(P(x, fy, fw, fh, { dim: s.dim }));
          it.push(T(String(i + 1).padStart(2, '0'), x, fy + fh + 26, 80, { font: s.kick.font, size: s.kick.size + 2, weight: 700, tracking: 0.1, c: 'accent' }));
          it.push(body(t, x, fy + fh + 26 + s.kick.size * 2.2, fw - 10, { size: s.body.size - 1, align: 'left' }));
        });
        return { items: it };
      },
      look: (c, h, n) => {
        const tw = 470, ax = M + tw + 90, aw = X1 - ax, ay = Y0, ah = Y1 - Y0;
        const r1 = Math.round((ah - GAP) * 0.58), r2 = ah - GAP - r1, bw = Math.round((aw - GAP) * 0.62);
        const sw = (aw - 2 * GAP) / 3;
        return { items: [...block(n, h, M, TOP, tw, L.m),
          P(ax, ay, bw, r1, { dim: s.dim }), P(ax + bw + GAP, ay, aw - bw - GAP, r1, { dim: s.dim }),
          P(ax, ay + r1 + GAP, sw, r2, { dim: s.dim }), P(ax + sw + GAP, ay + r1 + GAP, sw, r2, { dim: s.dim }), P(ax + 2 * (sw + GAP), ay + r1 + GAP, sw, r2, { dim: s.dim })] };
      },
      splitL: (c, h, n) => {
        const pw = s.frame ? 1000 - M : 1040;
        return { rc: s.frame ? null : '#ffffff', items: [P(X0, Y0, pw, Y1 - Y0, { dim: s.dim }), ...(s.frame ? [] : [topShade()]), ...block(n, h, X0 + pw + 110, TOP, W - M - (X0 + pw + 110), L.l)] };
      },
      splitR: (c, h, n) => {
        const pw = s.frame ? 1000 - M : 1040, px = X1 - pw;
        return { items: [...block(n, h, M, TOP, px - 110 - M, L.l), P(px, Y0, pw, Y1 - Y0, { dim: s.dim })] };
      },
      wide: (c, h, n) => {
        // One wide frame across the page, the words in two columns under it.
        const fh = s.frame ? 560 : 640, fy = s.frame ? TOP : 0;
        const ty = fy + fh + 56, cw = (W - 2 * M - 80) / 2;
        return { rc: s.frame ? null : '#ffffff', items: [P(X0, fy, X1 - X0, fh, { dim: s.dim }), ...(s.frame ? [] : [topShade()]),
          kick(n, h, M, ty, 800), head(h, M, ty + s.kick.size * 2.4, cw, {}), body(L.m, M + cw + 80, ty + s.kick.size * 2.4, cw)] };
      },
      palette: (c, h, n) => {
        const pw = s.frame ? 1000 - M : 1040, rx = X0 + pw + 110, rw = W - M - rx, sy = TOP + 330, sh = Math.min(92, (BOT - sy - 4 * 18) / 5);
        const it = [P(X0, Y0, pw, Y1 - Y0), ...(s.frame ? [] : [topShade()]), ...block(n, h, rx, TOP, rw, L.s)];
        for (let k = 0; k < 5; k++) {
          const y = sy + k * (sh + 18);
          it.push(S('rect', rx, y, sh * 1.6, sh, { fill: 'pic:0:' + k, radius: s.swatchRadius || 0 }));
          it.push(T('{hex:0:' + k + '}', rx + sh * 1.6 + 28, y + sh / 2 - s.kick.size * 0.7, 300, { font: s.kick.font, size: s.kick.size, weight: 600, tracking: 0.12, c: 'ink' }));
          it.push(T(['Shadow', 'Mid', 'Skin', 'Accent', 'Highlight'][k], rx + sh * 1.6 + 220, y + sh / 2 - s.kick.size * 0.7, 300, { font: s.kick.font, size: s.kick.size, tracking: 0.12, upper: true, c: 'ink', op: 0.6 }));
        }
        return { rc: s.frame ? null : '#ffffff', items: it };
      },
      cast: (c, h, n) => {
        const fw = (W - 2 * M - 2 * GAP) / 3, fy = TOP + 150, fh = BOT - fy - 110;
        const it = [...block(n, h, M, TOP, 1000, null)];
        L.cast.forEach(([role, t], i) => {
          const x = M + i * (fw + GAP);
          it.push(P(x, fy, fw, fh, { dim: s.dim }));
          it.push(kick('', role, x, fy + fh + 24, fw, 'accent'));
          it.push(body(t, x, fy + fh + 24 + s.kick.size * 2, fw, { size: s.body.size - 1, align: 'left' }));
        });
        return { items: it };
      },
      places: (c, h, n) => {
        const tw = 470, ax = M + tw + 90, aw = X1 - ax, ah = (Y1 - Y0 - GAP) / 2;
        return { items: [...block(n, h, M, TOP, tw, L.m),
          P(ax, Y0, aw, ah, { dim: s.dim }), P(ax, Y0 + ah + GAP, (aw - GAP) / 2, ah, { dim: s.dim }), P(ax + (aw + GAP) / 2, Y0 + ah + GAP, (aw - GAP) / 2, ah, { dim: s.dim })] };
      },
      full: (c, h, n) => ({ rc: '#ffffff', items: [P(0, 0, W, H, { dim: s.fullDim == null ? 0.1 : s.fullDim }), topShade(),
        S('rect', 0, H - 460, W, 460, { fill: '#000000', fadeTo: 'top', fadeAt: 0.2, op: 0.72 }),
        ...block(n, h, M, H - s.bottom - 250, 1000, L.s, { kc: s.fullKick || 'accent', hc: '#ffffff', bc: '#ffffff' })] }),
      refs: (c, h, n) => {
        const cols = 4, rows = 2, gy = TOP + 120, gw = (W - 2 * M - (cols - 1) * GAP) / cols, gh = (BOT - gy - (rows - 1) * GAP) / rows;
        const it = [kick(n, h, M, TOP, 800), head(h, M, TOP + s.kick.size * 2.4, 1200, { size: Math.min(s.head.size, 56) })];
        for (let r = 0; r < rows; r++) for (let k = 0; k < cols; k++) it.push(P(M + k * (gw + GAP), gy + r * (gh + GAP), gw, gh));
        return { items: it };
      },
      table: (c, h, n) => {
        const it = [...block(n, h, M, TOP, 560, L.s)], tx = 760, tw = W - M - tx, cx = [tx, tx + 420, tx + 680], ty = TOP + 20, rh = (BOT - ty) / 5.4;
        L.sched.forEach((r, i) => {
          const y = ty + i * rh;
          it.push(rule(tx, y, tw));
          it.push(T(r[0], cx[0], y + 24, 400, { font: s.head.font, size: Math.min(34, s.head.size * 0.5), weight: s.head.weight || 400, italic: !!s.head.italic, upper: !!s.head.upper, stretch: s.head.stretch, tracking: s.head.tracking || 0, c: 'ink' }));
          it.push(kick('', r[1], cx[1], y + 32, 240, 'accent'));
          it.push(body(r[2], cx[2], y + 28, W - M - cx[2], { align: 'left' }));
        });
        it.push(rule(tx, ty + 5 * rh, tw));
        return { items: it };
      },
      close: c => s.close(c, { M, TOP, BOT, kick, head, body, rule }),

      /* ---------- the B layouts: more ways to show pictures, more pages led by design ---------- */
      coverB: c => {
        const sx = Math.round(W * 0.5), fill = s.bFill || 'tint';
        const t = upper(c.title), sz = fit(t, sx - 2 * M, s.bTitle || 150, s.head.em);
        return { runner: false, items: [S('rect', 0, 0, sx, H, { fill }), P(sx, 0, W - sx, H, { dim: s.dim }),
          P(sx - 250, H - M - 380, 500, 330, { border: s.dark ? 'bg' : 'bg', bw: 12 }),
          kick('', c.client + '   ·   ' + c.director, M, M + 20, sx - 2 * M),
          T(t, M, 300, sx - 2 * M - 40, { font: s.head.font, size: sz, weight: s.head.weight || 400, italic: !!s.head.italic, tracking: s.head.tracking || 0, stretch: s.head.stretch, leading: 0.95, c: 'ink' }),
          kick('', 'Treatment  ·  ' + c.month, M, H - M - 20, 500, 'ink')] };
      },
      noteB: (c, h, n) => ({ items: [...block(n, h, M, TOP, 640, L.note, { title: s.noteTitle || 'A note from the director' }),
        T('— ' + c.director, M, BOT - 60, 640, { font: s.sign.font, size: s.sign.size, italic: !!s.sign.italic, weight: s.sign.weight || 400, c: 'ink' }),
        P(1000, Y0, 600, 640, { dim: s.dim }), P(1360, 560, 480, BOT - 560, { border: 'bg', bw: 12, dim: s.dim })] }),
      chapter: (c, h, n) => {
        const pw = 640, px = W - (s.frame ? M : 0) - pw, tw = px - 2 * M;
        return { bg: 'tint', items: [
          T(n, M - 10, M + 20, 700, { font: s.head.font, size: s.bNum || 300, weight: s.head.weight || 400, italic: !!s.head.italic, stretch: s.head.stretch, leading: 0.9, tracking: -0.02, c: 'accent' }),
          kick('', h, M, 560, tw), T(s.idea.upper === false ? L.idea : upper(L.idea), M, 610, tw, { role: 'idea', fit: true, font: s.idea.font || s.head.font, size: Math.round(s.idea.size * 0.62), weight: s.idea.weight || s.head.weight || 400,
            italic: !!s.idea.italic, leading: s.idea.leading || 1.1, tracking: s.idea.tracking || 0, stretch: s.head.stretch, c: 'ink' }),
          P(px, s.frame ? M : 0, pw, s.frame ? H - 2 * M : H, { dim: s.dim })] };
      },
      film: (c, h, n) => {
        const fw = (X1 - X0 - 3 * GAP) / 4, fy = TOP + 140, fh = BOT - fy - 170;
        const it = [kick(n, h, M, TOP, 800), head(h, M, TOP + s.kick.size * 2.4, 1200, { size: Math.min(s.head.size, 60) })];
        L.beats.forEach((t, i) => {
          const x = X0 + i * (fw + GAP);
          it.push(P(x, fy, fw, fh, { dim: s.dim }));
          it.push(T(String(i + 1).padStart(2, '0'), x + 22, fy + fh - 90, 200, { font: s.head.font, size: 64, weight: s.head.weight || 400, stretch: s.head.stretch, c: '#ffffff' }));
          it.push(body(t, x + (s.frame ? 0 : 22), fy + fh + 28, fw - 44, { size: s.body.size - 1, align: 'left' }));
        });
        return { items: it };
      },
      mosaic: (c, h, n) => {
        const ax = X0, ay = Y0, aw = X1 - X0, ah = Y1 - Y0, cw = (aw - 3 * GAP) / 4, rh = (ah - 2 * GAP) / 3;
        const cell = (col, row, cs, rs) => [ax + col * (cw + GAP), ay + row * (rh + GAP), cs * cw + (cs - 1) * GAP, rs * rh + (rs - 1) * GAP];
        const tc = cell(2, 1, 1, 1), pad = 26;
        return { rc: s.frame ? null : '#ffffff', items: [P(...cell(0, 0, 2, 2)), P(...cell(2, 0, 1, 1)), P(...cell(3, 0, 1, 2)), P(...cell(0, 2, 1, 1)), P(...cell(1, 2, 2, 1)), P(...cell(3, 2, 1, 1)),
          S('rect', tc[0], tc[1], tc[2], tc[3], { fill: 'tint' }),
          kick(n, h, tc[0] + pad, tc[1] + pad, tc[2] - 2 * pad), head(h, tc[0] + pad, tc[1] + pad + s.kick.size * 2.2, tc[2] - 2 * pad, { size: Math.min(s.head.size, 48) }),
          body(L.xs || 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.', tc[0] + pad, tc[1] + tc[3] - pad - s.body.size * 3.4, tc[2] - 2 * pad, { size: s.body.size - 2 })] };
      },
      diptych: (c, h, n) => {
        const band = 250, ih = (s.frame ? BOT : H) - band - Y0, hw = (X1 - X0 - GAP) / 2;
        return { rc: s.frame ? null : '#ffffff', items: [P(X0, Y0, hw, ih, { dim: s.dim }), P(X0 + hw + GAP, Y0, hw, ih, { dim: s.dim }), ...(s.frame ? [] : [topShade()]),
          kick(n, h, M, Y0 + ih + 50, 700), head(h, M, Y0 + ih + 50 + s.kick.size * 2.4, 820, { size: Math.min(s.head.size, 60) }), body(L.m, 1000, Y0 + ih + 56, W - M - 1000)] };
      },
      stripes: (c, h, n) => {
        const pw = 900, sx = X0 + pw + (s.frame ? GAP : 0), sw = (X1 - sx - 4 * (s.frame ? GAP : 0)) / 5, g = s.frame ? GAP : 0;
        const it = [P(X0, Y0, pw, Y1 - Y0), S('rect', X0, Y1 - 330, pw, 330, { fill: '#000000', fadeTo: 'top', fadeAt: 0.1, op: 0.7 }),
          kick(n, h, X0 + 60, Y1 - 250, pw - 120, '#ffffff'), head(h, X0 + 60, Y1 - 250 + s.kick.size * 2.4, pw - 120, { c: '#ffffff', size: Math.min(s.head.size, 64) })];
        for (let k = 0; k < 5; k++) {
          const x = sx + k * (sw + g);
          it.push(S('rect', x, Y0, sw, Y1 - Y0, { fill: 'pic:0:' + k }));
          it.push(T('{hex:0:' + k + '}', x + 20, Y1 - 60, sw - 30, { font: s.kick.font, size: s.kick.size, weight: 700, tracking: 0.1, c: '#ffffff' }));
        }
        return { rc: s.frame ? null : '#ffffff', items: it };
      },
      triptych: (c, h, n) => {
        const g = s.frame ? GAP : 4, fw = (X1 - X0 - 2 * g) / 3;
        const it = [];
        L.cast.forEach(([role, t], i) => {
          const x = X0 + i * (fw + g);
          it.push(P(x, Y0, fw, Y1 - Y0, { dim: s.dim }));
          it.push(S('rect', x, Y1 - 300, fw, 300, { fill: '#000000', fadeTo: 'top', fadeAt: 0.15, op: 0.75 }));
          it.push(kick('', role, x + 36, Y1 - 150, fw - 72, 'accent'));
          it.push(body(t, x + 36, Y1 - 150 + s.kick.size * 2, fw - 72, { c: '#ffffff', size: s.body.size - 1, align: 'left' }));
        });
        it.push(S('rect', X0, Y0, X1 - X0, 230, { fill: '#000000', fadeTo: 'bottom', fadeAt: 0.1, op: 0.55 }));
        it.push(kick(n, h, X0 + 36, Y0 + (s.frame ? 36 : TOP), 700, '#ffffff'));
        it.push(head(h, X0 + 36, Y0 + (s.frame ? 36 : TOP) + s.kick.size * 2.4, 900, { c: '#ffffff', size: Math.min(s.head.size, 64) }));
        return { rc: '#ffffff', items: it };
      },
      stack: (c, h, n) => ({ items: [P(X0, Y0, 1080 - X0, Y1 - Y0, { dim: s.dim }), P(900, 440, 440, Y1 - 440 - (s.frame ? 60 : 80), { border: 'bg', bw: 14, dim: s.dim }),
        ...block(n, h, 1440, TOP, W - M - 1440, L.m)] }),
      insetFull: (c, h, n) => ({ rc: '#ffffff', items: [P(0, 0, W, H, { dim: 0.08 }), topShade(), P(W - M - 560, TOP, 560, 380, { border: 'bg', bw: 12 }),
        S('rect', 0, H - 440, W, 440, { fill: '#000000', fadeTo: 'top', fadeAt: 0.2, op: 0.7 }),
        ...block(n, h, M, H - s.bottom - 240, 900, L.s, { kc: 'accent', hc: '#ffffff', bc: '#ffffff' })] }),
      pull: (c, h, n) => {
        const q = '“' + L.idea.replace(/\.$/, '') + '.”';
        return { items: [kick(n, h, M, TOP, 800), T(q, M, 330, 1180, { role: 'idea', fit: true, font: s.head.font, size: Math.min(88, Math.round(s.head.size * 1.05)), weight: s.head.weight || 400, italic: !!s.head.italic || /Serif|Italiana/.test(s.head.font),
          upper: !!s.head.upper, stretch: s.head.stretch, tracking: s.head.tracking || 0, leading: 1.08, c: 'ink' }), rule(M, 760, 120, 'accent'), body(L.s, M, 800, 760),
          P(X1 - 520, Y0, 520, Y1 - Y0, { dim: s.dim })] };
      },
      band: (c, h, n) => {
        const by = 330, bh = 420, g = s.frame ? GAP : 0, bw = (X1 - X0 - 2 * g) / 3;
        return { items: [kick(n, h, M, TOP, 800), head(h, M, TOP + s.kick.size * 2.4, 1200, { size: Math.min(s.head.size, 60) }),
          P(X0, by, bw * 1.3, bh), P(X0 + bw * 1.3 + g, by, bw * 0.7, bh), P(X0 + 2 * bw + 2 * g, by, bw, bh),
          body(L.m, M, by + bh + 56, 760), body(L.s, 1000, by + bh + 56, W - M - 1000)] };
      },
      refsB: (c, h, n) => {
        const ax = X0, ay = Y0, aw = X1 - X0, ah = Y1 - Y0, g = 4, cw = (aw - 4 * g) / 5, rh = (ah - 2 * g) / 3;
        const cell = (col, row, cs, rs) => [ax + col * (cw + g), ay + row * (rh + g), cs * cw + (cs - 1) * g, rs * rh + (rs - 1) * g];
        const it = [P(...cell(0, 0, 2, 2)), P(...cell(2, 0, 1, 1)), P(...cell(3, 0, 2, 1)), P(...cell(2, 1, 2, 1)), P(...cell(4, 1, 1, 2)), P(...cell(0, 2, 1, 1)), P(...cell(1, 2, 1, 1)), P(...cell(2, 2, 2, 1))];
        const tc = cell(0, 0, 2, 2);
        it.push(S('rect', tc[0], tc[1] + tc[3] - 200, tc[2], 200, { fill: '#000000', fadeTo: 'top', fadeAt: 0.1, op: 0.65 }));
        it.push(kick(n, h, tc[0] + 36, tc[1] + tc[3] - 130, 600, '#ffffff'));
        it.push(head(h, tc[0] + 36, tc[1] + tc[3] - 130 + s.kick.size * 2.2, tc[2] - 72, { c: '#ffffff', size: Math.min(s.head.size, 52) }));
        return { rc: s.frame ? null : '#ffffff', items: it };
      },
      timeline: (c, h, n) => {
        const it = [...block(n, h, M, TOP, 900, L.s)], tx = M, tw = W - 2 * M, by = 620, weeks = [2, 1, 1, 3, 1], tot = 8;
        let x = tx;
        L.sched.forEach((r, i) => {
          const w = tw * weeks[i] / tot;
          it.push(S('rect', x, by, w - 6, 16, { fill: i % 2 ? 'ink' : 'accent', op: i % 2 ? 0.55 : 1 }));
          it.push(T(r[0], x, by - 70, w - 20, { font: s.head.font, size: 26, weight: s.head.weight || 400, italic: !!s.head.italic, upper: !!s.head.upper, stretch: s.head.stretch, c: 'ink' }));
          it.push(kick('', r[1], x, by + 44, w - 20, 'accent'));
          it.push(body(r[2], x, by + 44 + s.kick.size * 2.2, w - 30, { size: s.body.size - 2, align: 'left' }));
          x += w;
        });
        return { items: it };
      },
      closeB: c => {
        const g = s.frame ? GAP : 0, sw = (X1 - X0 - 3 * g) / 4, sy = 600;
        return { runner: false, items: [T(s.head.upper ? 'THANK YOU' : 'Thank you', M, 250, W - 2 * M, { font: s.head.font, size: s.bThanks || 170, weight: s.head.weight || 400, italic: !!s.head.italic, stretch: s.head.stretch, tracking: s.head.tracking || 0, leading: 0.95, c: 'ink' }),
          kick('', c.director + '   ·   name@yourstudio.com', M + 6, 490, 1200, 'accent'),
          P(X0, sy, sw, (s.frame ? BOT : H) - sy), P(X0 + (sw + g), sy, sw, (s.frame ? BOT : H) - sy), P(X0 + 2 * (sw + g), sy, sw, (s.frame ? BOT : H) - sy), P(X0 + 3 * (sw + g), sy, sw, (s.frame ? BOT : H) - sy)] };
      },
    };
    const orderB = [['coverB'], ['noteB', 'Director’s note'], ['chapter', 'The idea'], ['mosaic', 'Look & feel'], ['diptych', 'Cinematography'],
      ['stripes', 'Light & colour'], ['triptych', 'Casting'], ['stack', 'Wardrobe & styling'], ['insetFull', 'Locations & design'], ['pull', 'Edit & pace'],
      ['band', 'Sound & music'], ['film', 'Story'], ['refsB', 'References'], ['timeline', 'Production'], ['closeB']];
    const order = s.b ? orderB : [['cover'], ['note', 'Director’s note'], ['idea', 'The idea'], ['look', 'Look & feel'], [s.lay.cine || 'splitL', 'Cinematography'],
      ['palette', 'Light & colour'], ['cast', 'Casting'], [s.lay.ward || 'splitR', 'Wardrobe & styling'], ['places', 'Locations & design'], ['full', 'Edit & pace'],
      [s.lay.sound || 'wide', 'Sound & music'], ['beats', 'Story'], ['refs', 'References'], ['table', 'Production'], ['close']];
    return { id: s.id, name: s.name, after: s.after, feel: s.feel, pal: s.pal, dark, want: s.want, order, D,
      runner: { font: s.kick.font, size: s.kick.size, style: s.runStyle || 'pad', inset: 48, top: 6, upper: true },   // just touching the top edge, on every template
      // Its type, by what the words are — so a page from another template can take this one's look.
      type: { head: { font: s.head.font, weight: s.head.weight || 400, italic: !!s.head.italic, upper: !!s.head.upper, tracking: s.head.tracking || 0, stretch: s.head.stretch || 100 },
        idea: { font: s.idea.font || s.head.font, weight: s.idea.weight || s.head.weight || 400, italic: !!s.idea.italic, upper: s.idea.upper !== false && !!s.head.upper, tracking: s.idea.tracking || 0 },
        body: { font: s.body.font, weight: s.body.weight || 400, italic: false, upper: false, tracking: 0 },
        kick: { font: s.kick.font, weight: s.kick.weight || 500, italic: false, upper: s.kick.upper !== false, tracking: s.kick.tracking || 0.16 },
        sign: { font: s.sign.font, weight: s.sign.weight || 400, italic: !!s.sign.italic, upper: !!s.sign.upper, tracking: 0 } } };
  }

  // Every template comes twice: A, and B — more ways to show pictures, more pages led by the design.
  const both = cfg => [make(cfg), make(Object.assign({}, cfg, { id: cfg.id + '-b', name: cfg.name + ' B', b: true }))];

  /* ------------------------------------------------------------------ 1 Noir: black, cinematic, small type */
  const noir = both({ id: 'noir', name: 'Noir', after: 'Night', feel: 'Black pages, pictures to the edge, small clean capitals and justified text. Lets the images do the work.',
    pal: { bg: '#0a0a0a', ink: '#ecebe7', accent: '#9b958c', tint: '#1c1c1c' }, dark: true,
    want: { lum: 0.24, sat: 0.3, hues: [] },
    M: 88, top: 150, bottom: 88, gut: 8, frame: false, dim: 0.05, rules: false, ruleOp: 0.35,
    kick: { font: 'Inter Tight', size: 13, weight: 600, tracking: 0.22, c: 'accent' },
    head: { font: 'Inter Tight', size: 40, weight: 700, upper: true, tracking: 0.02, leading: 1.1, em: 0.66, after: 30 },
    body: { font: 'Inter Tight', size: 19, leading: 1.5, align: 'justify' },
    sign: { font: 'Instrument Serif', size: 34, italic: true },
    idea: { size: 66, y: 420, w: 1400, font: 'Inter Tight', weight: 500, leading: 1.12, upper: false, em: 0.52 },
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.25 }), S('rect', 0, H - 520, W, 520, { fill: '#000000', fadeTo: 'top', fadeAt: 0.1, op: 0.8 }),
      k.kick('', c.client + '   ·   ' + c.director, k.M, H - k.M - 170, 1200, '#ffffff'),
      T(c.title.toUpperCase(), k.M, H - k.M - 128, 1600, { font: 'Inter Tight', size: fit(c.title.toUpperCase(), 1600, 110, 0.68), weight: 700, tracking: 0.01, leading: 1, c: '#ffffff' })] }),
    close: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.6 }), T('THANK YOU', 0, 470, W, { font: 'Inter Tight', size: 40, weight: 700, tracking: 0.4, align: 'center', c: '#ffffff' }),
      T(c.director.toUpperCase() + '   ·   ' + c.title.toUpperCase(), 0, 548, W, { font: 'Inter Tight', size: 13, weight: 600, tracking: 0.22, align: 'center', c: 'accent' })] }),
  });

  /* ------------------------------------------------------------------ 2 Gallery: white space, a serif, framed pictures */
  const gallery = both({ id: 'gallery', name: 'Gallery', after: 'Paper', feel: 'Warm white pages, framed pictures with room around them, a classic serif and quiet captions.',
    pal: { bg: '#f3f1ec', ink: '#161514', accent: '#8c7b66', tint: '#e6e1d8' }, dark: false,
    want: { lum: 0.56, sat: 0.3, hues: ['white', 'grey', 'brown', 'green', 'blue'] },
    M: 120, top: 170, bottom: 110, gut: 24, frame: true, rules: true, ruleOp: 0.4,
    kick: { font: 'Inter Tight', size: 12, weight: 600, tracking: 0.24, c: 'accent' },
    head: { font: 'Instrument Serif', size: 68, weight: 400, upper: false, leading: 1.02, em: 0.42, after: 34 },
    body: { font: 'Inter Tight', size: 18, leading: 1.65, align: 'left' },
    sign: { font: 'Instrument Serif', size: 38, italic: true },
    idea: { size: 84, y: 400, w: 1500, font: 'Instrument Serif', leading: 1.05, italic: true, upper: false, em: 0.42 },
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(840, k.M, W - k.M - 840, H - 2 * k.M),
      k.kick('', c.client, k.M, 360, 600), T(c.title, k.M, 400, 640, { font: 'Instrument Serif', size: fit(c.title, 640, 120, 0.42), leading: 0.98, c: 'ink' }),
      k.rule(k.M, H - k.M - 80, 600), T('A treatment by ' + c.director, k.M, H - k.M - 56, 600, { font: 'Instrument Serif', size: 28, italic: true, c: 'ink' })] }),
    close: (c, k) => ({ runner: false, items: [P(840, k.M, W - k.M - 840, H - 2 * k.M),
      T('Thank you', k.M, 420, 640, { font: 'Instrument Serif', size: 110, c: 'ink' }), k.rule(k.M, 590, 120),
      T(c.director + '\nname@yourstudio.com', k.M, 620, 640, { font: 'Inter Tight', size: 18, leading: 1.7, c: 'ink', op: 0.8 })] }),
  });

  /* ------------------------------------------------------------------ 3 Anthem: loud, condensed, one hot colour */
  const anthem = both({ id: 'anthem', name: 'Anthem', after: 'Stage', feel: 'Dark, loud and graphic: towering condensed capitals, one hot accent, pictures edge to edge.',
    pal: { bg: '#0e0d0d', ink: '#f3efe9', accent: '#ff4a1c', tint: '#262322' }, dark: true,
    want: { lum: 0.33, sat: 0.6, hues: ['red', 'orange', 'pink', 'purple', 'yellow'] },
    M: 80, top: 140, bottom: 80, gut: 0, frame: false, dim: 0, rules: false,
    kick: { font: 'Inter Tight', size: 14, weight: 700, tracking: 0.16, c: 'accent' },
    head: { font: 'Anton', size: 112, weight: 400, upper: true, leading: 0.92, em: 0.52, after: 34 },
    body: { font: 'Inter Tight', size: 20, leading: 1.5, align: 'left' },
    sign: { font: 'Anton', size: 40, upper: true },
    idea: { size: 150, y: 330, w: 1760, font: 'Anton', leading: 0.9, c: 'accent', em: 0.5 },
    fullKick: 'accent',
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.4 }),
      k.kick('', c.client + '  ·  dir. ' + c.director, k.M, 150, 1200, '#ffffff'),
      T(c.title.toUpperCase(), k.M, 210, W - 2 * k.M, { font: 'Anton', size: fit(c.title.toUpperCase(), W - 2 * k.M, 340, 0.46), leading: 0.86, c: 'accent' })] }),
    close: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.55 }), T('THANK YOU', k.M, 330, W - 2 * k.M, { font: 'Anton', size: 300, leading: 0.9, c: 'accent' }),
      k.kick('', c.director + '  ·  ' + c.title, k.M, 640, 1200, '#ffffff')] }),
  });

  /* ------------------------------------------------------------------ 4 System: Swiss grid, hairlines, numbers */
  const system = both({ id: 'system', name: 'System', after: 'Grid', feel: 'A strict grid on bright white: bold grotesk, hairline rules, big section numbers, one electric blue.',
    pal: { bg: '#f4f4f1', ink: '#0f0f10', accent: '#2346ff', tint: '#e4e4df' }, dark: false,
    want: { lum: 0.52, sat: 0.3, hues: ['blue', 'grey', 'white', 'teal'] },
    M: 80, top: 160, bottom: 80, gut: 16, frame: true, rules: true, ruleOp: 1,
    kick: { font: 'Archivo', size: 13, weight: 600, tracking: 0.12, c: 'accent', sep: '   ' },
    head: { font: 'Archivo', size: 76, weight: 700, upper: false, tracking: -0.03, leading: 0.98, em: 0.58, after: 38 },
    body: { font: 'Inter Tight', size: 17, leading: 1.6, align: 'left' },
    sign: { font: 'Archivo', size: 26, weight: 600 },
    idea: { size: 96, y: 360, w: 1500, font: 'Archivo', weight: 700, tracking: -0.03, leading: 1, upper: false, em: 0.52 },
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(1000, k.M, W - k.M - 1000, H - 2 * k.M),
      T(c.title, k.M, k.M - 10, 860, { font: 'Archivo', size: fit(c.title, 860, 150, 0.58), weight: 700, tracking: -0.04, leading: 0.92, c: 'ink' }),
      ...[['Director', c.director], ['Client', c.client], ['Date', c.month], ['Version', '01']].flatMap(([a, b], i) => [k.rule(k.M, 700 + i * 72, 840),
        T(a.toUpperCase(), k.M, 718 + i * 72, 240, { font: 'Archivo', size: 13, weight: 600, tracking: 0.12, c: 'accent' }), T(b, k.M + 260, 714 + i * 72, 580, { font: 'Inter Tight', size: 20, c: 'ink' })]),
      k.rule(k.M, 700 + 4 * 72, 840)] }),
    close: (c, k) => ({ runner: false, items: [T('Thank you.', k.M, 360, 1400, { font: 'Archivo', size: 180, weight: 700, tracking: -0.05, c: 'ink' }), k.rule(k.M, 620, W - 2 * k.M),
      T(c.director, k.M, 650, 600, { font: 'Inter Tight', size: 20, c: 'ink' }), T('name@yourstudio.com', 700, 650, 600, { font: 'Inter Tight', size: 20, c: 'accent' })] }),
  });

  /* ------------------------------------------------------------------ 5 Frame: widescreen, letterbox, script slugs */
  const frame = both({ id: 'frame', name: 'Frame', after: 'Widescreen', feel: 'Every picture in a widescreen frame on black, with script-style slug lines and an amber accent.',
    pal: { bg: '#050505', ink: '#e8e4dc', accent: '#d8ae62', tint: '#161616' }, dark: true,
    want: { lum: 0.3, sat: 0.4, hues: ['blue', 'teal', 'orange', 'yellow', 'brown'] },
    M: 120, top: 150, bottom: 90, gut: 12, frame: true, dim: 0, rules: false, beatAspect: 2.39,
    kick: { font: 'Courier Prime', size: 15, weight: 700, tracking: 0.08, c: 'accent', sep: '  ·  ' },
    head: { font: 'Courier Prime', size: 34, weight: 700, upper: true, tracking: 0.08, leading: 1.2, em: 0.62, after: 26 },
    body: { font: 'Inter Tight', size: 18, leading: 1.6, align: 'left' },
    sign: { font: 'Courier Prime', size: 22, weight: 700 },
    idea: { size: 54, y: 440, w: 1500, font: 'Courier Prime', weight: 700, leading: 1.3, upper: true, em: 0.64 },
    fullDim: 0,
    lay: { cine: 'wide', ward: 'wide', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(0, 140, W, 803),
      T('FADE IN:', k.M, 64, 400, { font: 'Courier Prime', size: 18, weight: 700, tracking: 0.08, c: 'accent' }),
      T(c.title.toUpperCase(), k.M, 968, 1100, { font: 'Courier Prime', size: 34, weight: 700, tracking: 0.08, c: 'ink' }),
      T(c.client.toUpperCase() + '  ·  DIR. ' + c.director.toUpperCase(), W - k.M - 800, 976, 800, { font: 'Courier Prime', size: 17, weight: 700, tracking: 0.08, align: 'right', c: 'accent' })] }),
    close: (c, k) => ({ runner: false, items: [P(0, 140, W, 803, { dim: 0.5 }), T('FADE OUT.', 0, 500, W, { font: 'Courier Prime', size: 44, weight: 700, tracking: 0.12, align: 'center', c: 'ink' }),
      T('THANK YOU  ·  ' + c.director.toUpperCase(), 0, 968, W, { font: 'Courier Prime', size: 17, weight: 700, tracking: 0.1, align: 'center', c: 'accent' })] }),
  });

  /* ------------------------------------------------------------------ 6 Soft: sand, a thin display serif, reading type */
  const soft = both({ id: 'soft', name: 'Soft', after: 'Sand', feel: 'Warm sand pages, a thin display serif in capitals, a reading serif for the words. Calm and tactile.',
    pal: { bg: '#e8e1d5', ink: '#2a241f', accent: '#8a5a36', tint: '#d9cfbf' }, dark: false,
    want: { lum: 0.5, sat: 0.4, hues: ['orange', 'brown', 'yellow', 'red', 'green'] },
    M: 110, top: 170, bottom: 100, gut: 20, frame: true, rules: true, ruleOp: 0.35,
    kick: { font: 'Inter Tight', size: 12, weight: 600, tracking: 0.26, c: 'accent' },
    head: { font: 'Italiana', size: 76, weight: 400, upper: true, tracking: 0.04, leading: 1.02, em: 0.62, after: 36 },
    body: { font: 'Merriweather', size: 16, leading: 1.85, align: 'left' },
    sign: { font: 'Italiana', size: 40, upper: true },
    idea: { size: 76, y: 400, w: 1500, font: 'Italiana', leading: 1.12, tracking: 0.02, em: 0.66 },
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(k.M, k.M, 1060, H - 2 * k.M),
      k.kick('', c.client, 1260, 380, 560), T(c.title.toUpperCase(), 1260, 420, 560, { font: 'Italiana', size: fit(c.title.toUpperCase(), 560, 110, 0.62), tracking: 0.04, leading: 1, c: 'ink' }),
      k.rule(1260, H - k.M - 90, 200), T('A treatment by ' + c.director, 1260, H - k.M - 64, 560, { font: 'Merriweather', size: 17, italic: true, c: 'ink' })] }),
    close: (c, k) => ({ runner: false, items: [P(k.M, k.M, 1060, H - 2 * k.M), T('THANK YOU', 1260, 440, 560, { font: 'Italiana', size: 96, tracking: 0.04, c: 'ink' }), k.rule(1260, 590, 200),
      T(c.director + '\nname@yourstudio.com', 1260, 620, 560, { font: 'Merriweather', size: 17, leading: 1.9, c: 'ink' })] }),
  });


  /* ------------------------------------------------------------------ 7 Signal: modern, digital, playful type */
  const signal = both({ id: 'signal', name: 'Signal', after: 'Screen', feel: 'Modern and digital: wide mono display letters, outlined statements, rounded frames and one electric lime.',
    pal: { bg: '#0c0d11', ink: '#e9edf3', accent: '#c8ff3c', tint: '#1b1d24' }, dark: true,
    want: { lum: 0.35, sat: 0.5, hues: ['blue', 'purple', 'teal', 'pink', 'green'] },
    M: 90, top: 160, bottom: 90, gut: 14, frame: true, dim: 0, rules: false, picRadius: 22, bFill: 'accent', bNum: 280,
    kick: { font: 'Inter Tight', size: 13, weight: 700, tracking: 0.14, c: 'accent', sep: '  /  ' },
    head: { font: 'Rubik Mono One', size: 58, weight: 400, upper: true, tracking: -0.01, leading: 1.02, em: 1.08, after: 34 },
    body: { font: 'Inter Tight', size: 18, leading: 1.6, align: 'left' },
    sign: { font: 'Rubik Mono One', size: 24 },
    idea: { size: 92, y: 380, w: 1720, font: 'Rubik Mono One', leading: 1.02, outline: 1.6, em: 0.86 },
    bTitle: 120, bThanks: 150,
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.35 }),
      T('[ ' + c.client.toUpperCase() + ' ]', k.M, k.M, 900, { font: 'Inter Tight', size: 15, weight: 700, tracking: 0.14, c: 'accent' }),
      T(c.title.toUpperCase(), k.M, 360, W - 2 * k.M, { font: 'Rubik Mono One', size: fit(c.title.toUpperCase(), W - 2 * k.M, 170, 0.86), leading: 0.98, outline: 2.4, c: '#ffffff' }),
      T(c.title.toUpperCase(), k.M + 10, 370, W - 2 * k.M, { font: 'Rubik Mono One', size: fit(c.title.toUpperCase(), W - 2 * k.M, 170, 0.86), leading: 0.98, c: 'accent', op: 0.9 }),
      T('DIR. ' + c.director.toUpperCase() + '  /  ' + c.month, k.M, H - k.M - 20, 1200, { font: 'Inter Tight', size: 15, weight: 700, tracking: 0.14, c: '#ffffff' })] }),
    close: (c, k) => ({ runner: false, items: [T('THANK\nYOU', k.M, 260, W - 2 * k.M, { font: 'Rubik Mono One', size: 230, leading: 0.95, outline: 2.4, c: 'ink' }),
      T('THANK\nYOU', k.M + 14, 274, W - 2 * k.M, { font: 'Rubik Mono One', size: 230, leading: 0.95, c: 'accent' }),
      T('[ ' + c.director.toUpperCase() + '  /  NAME@YOURSTUDIO.COM ]', k.M, H - k.M - 20, 1400, { font: 'Inter Tight', size: 15, weight: 700, tracking: 0.14, c: 'ink' })] }),
  });

  /* ------------------------------------------------------------------ 8 Reel: analogue, film, typewriter */
  const reel = both({ id: 'reel', name: 'Reel', after: 'Film stock', feel: 'Analogue and filmic: typewriter type on warm paper, pictures in thick film-frame borders, a Kodak orange.',
    pal: { bg: '#efe6d3', ink: '#231c15', accent: '#d9711c', tint: '#e2d4b8' }, dark: false,
    want: { lum: 0.45, sat: 0.4, hues: ['orange', 'brown', 'yellow', 'red', 'green'] },
    M: 110, top: 170, bottom: 100, gut: 22, frame: true, rules: true, ruleOp: 0.5, picBorder: '#141210', picBw: 14, bFill: 'tint', bNum: 260,
    kick: { font: 'Courier Prime', size: 15, weight: 700, tracking: 0.06, c: 'accent', sep: ' — ' },
    head: { font: 'Courier Prime', size: 46, weight: 700, upper: true, tracking: 0.02, leading: 1.12, em: 0.78, after: 30 },
    body: { font: 'Courier Prime', size: 17, weight: 400, leading: 1.6, align: 'left' },
    sign: { font: 'Instrument Serif', size: 40, italic: true },
    idea: { size: 58, y: 420, w: 1500, font: 'Courier Prime', weight: 700, leading: 1.3, upper: false, em: 0.62 },
    bTitle: 110, bThanks: 130,
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(k.M, k.M, 1080, H - 2 * k.M),
      T('ROLL 01  ·  ' + c.month, 1290, k.M, 520, { font: 'Courier Prime', size: 15, weight: 700, tracking: 0.08, c: 'accent' }),
      T(c.title.toUpperCase(), 1290, 380, 520, { font: 'Courier Prime', size: fit(c.title.toUpperCase(), 520, 76, 0.62), weight: 700, leading: 1.08, c: 'ink' }),
      k.rule(1290, H - k.M - 110, 520), T('A treatment by ' + c.director + '\nfor ' + c.client, 1290, H - k.M - 86, 520, { font: 'Courier Prime', size: 18, leading: 1.5, c: 'ink' })] }),
    close: (c, k) => ({ runner: false, items: [P(k.M, k.M, 1080, H - 2 * k.M), T('THE END.', 1290, 420, 520, { font: 'Courier Prime', size: 76, weight: 700, c: 'ink' }), k.rule(1290, 540, 200),
      T('Thank you.\n' + c.director + '\nname@yourstudio.com', 1290, 570, 520, { font: 'Courier Prime', size: 18, leading: 1.7, c: 'ink' })] }),
  });

  /* ------------------------------------------------------------------ 9 Vogue: fashion forward, editorial, sharp */
  const vogue = both({ id: 'vogue', name: 'Vogue', after: 'Cover story', feel: 'Fashion forward and sharp: a razor serif at magazine sizes, pictures edge to edge, black, white and one red.',
    pal: { bg: '#fbfaf8', ink: '#0b0b0b', accent: '#d7001f', tint: '#efece6' }, dark: false,
    want: { lum: 0.55, sat: 0.35, hues: ['red', 'pink', 'white', 'grey', 'black'] },
    M: 80, top: 150, bottom: 80, gut: 0, frame: false, dim: 0, rules: false, bFill: 'ink', bNum: 360,
    kick: { font: 'Inter Tight', size: 12, weight: 700, tracking: 0.3, c: 'accent', sep: '  ' },
    head: { font: 'Instrument Serif', size: 120, weight: 400, upper: false, tracking: -0.03, leading: 0.9, em: 0.4, after: 30 },
    body: { font: 'Inter Tight', size: 17, leading: 1.6, align: 'justify' },
    sign: { font: 'Instrument Serif', size: 44, italic: true },
    idea: { size: 128, y: 330, w: 1760, font: 'Instrument Serif', leading: 0.95, italic: true, upper: false, em: 0.4 },
    bTitle: 230, bThanks: 260,
    lay: { cine: 'splitL', ward: 'splitR', sound: 'wide' },
    cover: (c, k) => ({ runner: false, items: [P(0, 0, W, H, { dim: 0.12 }),
      T(c.title, 0, 60, W, { font: 'Instrument Serif', size: fit(c.title, W - 120, 330, 0.42), leading: 0.9, tracking: -0.04, align: 'center', c: '#ffffff' }),
      T(c.client.toUpperCase() + '     ' + c.director.toUpperCase() + '     ' + c.month, 0, H - 70, W, { font: 'Inter Tight', size: 13, weight: 700, tracking: 0.3, align: 'center', c: '#ffffff' })] }),
    close: (c, k) => ({ runner: false, items: [P(960, 0, 960, H), T('Thank\nyou.', k.M, 300, 860, { font: 'Instrument Serif', size: 260, leading: 0.86, tracking: -0.04, italic: true, c: 'ink' }),
      T(c.director.toUpperCase() + '     NAME@YOURSTUDIO.COM', k.M, H - k.M - 20, 860, { font: 'Inter Tight', size: 12, weight: 700, tracking: 0.3, c: 'accent' })] }),
  });

  // The sample pictures every template opens with (Resources/shell/samples) — swapped for your own stills in a click.
  // For your own use: before Needed Tools is sold, replace these with stills that are ours to ship.
  const SAMPLES = [{"id":"s000","a":1.627,"palette":["#010101","#8c8c8c","#050505","#606060","#b5b5b5"],"group":"Nike"},{"id":"s003","a":1.404,"palette":["#040404","#2c2c2c","#181818","#0b0b0b","#080808"],"group":"Nike"},{"id":"s006","a":1.779,"palette":["#1b1b1b","#0b0b0b","#161616","#111111","#333333"],"group":"Nike"},{"id":"s010","a":1.779,"palette":["#0a0a0a","#5e5e5e","#868686","#393939","#232323"],"group":"Nike"},{"id":"s019","a":1.779,"palette":["#030303","#261b18","#694c3f","#090809","#020303"],"group":"Nike"},{"id":"s023","a":1.333,"palette":["#1b1b1b","#111111","#090909","#383838","#0d0d0d"],"group":"Nike"},{"id":"s024","a":1.987,"palette":["#525252","#575757","#5f5f5f","#666666","#5c5c5c"],"group":"Nike"},{"id":"s026","a":1.333,"palette":["#080b0f","#344442","#415555","#26302e","#161c1a"],"group":"Nike"},{"id":"s030","a":1.447,"palette":["#0a0a0a","#292929","#1b1b1b","#434343","#111111"],"group":"Nike"},{"id":"s036","a":1.948,"palette":["#110c0b","#373532","#365159","#180f0d","#271c17"],"group":"MW"},{"id":"s037","a":1.786,"palette":["#742923","#0e0c12","#67251f","#1e1217","#471c1a"],"group":"MW"},{"id":"s038","a":1.777,"palette":["#090b10","#181217","#371316","#180d11","#3f2021"],"group":"MW"},{"id":"s044","a":2.045,"palette":["#0f0a06","#1e0d06","#311c10","#252822","#5e381e"],"group":"MW"},{"id":"s045","a":1.996,"palette":["#0a070c","#1d0d0d","#2c160e","#662914","#4b1a0f"],"group":"MW"},{"id":"s046","a":1.775,"palette":["#030305","#33272b","#1c1112","#5e5256","#0d0b0e"],"group":"MW"},{"id":"s048","a":1.718,"palette":["#26191e","#111018","#422733","#262647","#3b3543"],"group":"MW"},{"id":"s058","a":0.776,"palette":["#4d484f","#969d9f","#9b7266","#b8c3bc","#756c72"],"group":"MW"},{"id":"s064","a":2.013,"palette":["#866d44","#5e4721","#3d2c0f","#796039","#69522b"],"group":"Juicy"},{"id":"s065","a":1.5,"palette":["#1c293a","#080c0b","#4a6267","#15141b","#080a0a"],"group":"Juicy"},{"id":"s069","a":1.779,"palette":["#140e10","#160f11","#3b2c21","#585249","#1e1312"],"group":"Juicy"},{"id":"s076","a":1.498,"palette":["#060708","#75796a","#5a5b50","#0f0e0e","#292521"],"group":"Juicy"},{"id":"s085","a":1.368,"palette":["#191d18","#353327","#5c4d35","#b2c8b0","#424738"],"group":"Juicy"},{"id":"s087","a":1.333,"palette":["#0f1537","#5b3d4a","#2d3853","#452037","#585164"],"group":"Juicy"},{"id":"s092","a":1.779,"palette":["#0f0c17","#596e69","#313d47","#4a5a5c","#252a36"],"group":"Juicy"},{"id":"s093","a":1.779,"palette":["#131418","#3a595c","#1b282e","#8ba196","#5f7a7a"],"group":"Juicy"},{"id":"s096","a":1.779,"palette":["#0d1111","#8b594b","#2a201a","#5b423f","#a36f5c"],"group":"Juicy"},{"id":"s104","a":1.775,"palette":["#1a2326","#8f9f8f","#9bbdb9","#bcc2b3","#816947"],"group":"Juicy"},{"id":"s107","a":1.779,"palette":["#ea7c42","#fddbac","#f4ce9e","#7d321b","#fef6e6"],"group":"Juicy"},{"id":"s116","a":1.711,"palette":["#d9dccd","#3d3a44","#c7c6b8","#dedfd0","#dbdece"],"group":"Juicy"},{"id":"s121","a":2.028,"palette":["#08050c","#13111a","#12080d","#2b272f","#11050a"],"group":"Lexus"},{"id":"s122","a":2.028,"palette":["#959fa0","#161615","#424d3a","#899494","#68766e"],"group":"Lexus"},{"id":"s128","a":1.782,"palette":["#010101","#4a5c5d","#020101","#000000","#000101"],"group":"Lexus"},{"id":"s129","a":0.788,"palette":["#372f26","#636149","#c4c4bc","#a7a694","#817868"],"group":"Lexus"},{"id":"s130","a":2.486,"palette":["#4d779e","#375e84","#5684aa","#6089ae","#6e95b7"],"group":"Lexus"},{"id":"s131","a":2.026,"palette":["#08080d","#0c0c11","#15151a","#09080d","#2c2d35"],"group":"Lexus"},{"id":"s143","a":2.031,"palette":["#0f0e14","#252d3b","#1c1d29","#324354","#16151d"],"group":"Lexus"},{"id":"s144","a":2.074,"palette":["#0f1828","#286192","#103d65","#17436b","#72a6d1"],"group":"Lexus"},{"id":"s145","a":1.515,"palette":["#0d111b","#8c8e8f","#b4b5b6","#575c65","#202f4c"],"group":"Lexus"},{"id":"s156","a":2.026,"palette":["#b0aeac","#dfdede","#e7e7e7","#8e8a86","#ececed"],"group":"Lexus"},{"id":"s157","a":2.174,"palette":["#010102","#c8d5d1","#8fa9ac","#14232c","#010100"],"group":"Lexus"},{"id":"s161","a":1.236,"palette":["#524750","#c8d0df","#d0d6e8","#d6d9ea","#70787c"],"group":"Lexus"},{"id":"s162","a":0.978,"palette":["#403924","#1b1b15","#584e35","#2a2d26","#908767"],"group":"Lexus"},{"id":"s174","a":1.442,"palette":["#4a5871","#394963","#43526b","#303b52","#3f4c65"],"group":"Sbadu"},{"id":"s175","a":1.657,"palette":["#042d26","#a38435","#6b652f","#bb9742","#6d1c25"],"group":"Sbadu"},{"id":"s178","a":1.852,"palette":["#9c8b6c","#241910","#4a2f19","#c5bda2","#a5a796"],"group":"Sbadu"},{"id":"s180","a":1.727,"palette":["#110e0f","#2c1b13","#9eaaa3","#432f24","#6d6556"],"group":"Sbadu"},{"id":"s182","a":1.788,"palette":["#22110d","#b6ac9c","#6b4a3b","#abab93","#56221e"],"group":"Sbadu"},{"id":"s183","a":1.777,"palette":["#201a17","#996c34","#4f2e1b","#a98f65","#6a482e"],"group":"Sbadu"},{"id":"s184","a":1.658,"palette":["#1c1f24","#0c0f14","#2a2d32","#a1a4a9","#c0c3c8"],"group":"Sbadu"},{"id":"s186","a":2.256,"palette":["#384851","#0d161f","#2f3f4a","#1a2933","#24323c"],"group":"Sbadu"},{"id":"s187","a":1.601,"palette":["#83a6a8","#345e72","#213f51","#92aca6","#a2b7ad"],"group":"Sbadu"},{"id":"s197","a":1.459,"palette":["#2d1a2e","#825b47","#3f2931","#e19b5e","#a68464"],"group":"Sbadu"},{"id":"s203","a":1.321,"palette":["#281a11","#a1abaa","#d0c8b0","#b6b8ac","#eadabd"],"group":"Sbadu"},{"id":"s205","a":2.35,"palette":["#726c59","#2e271f","#3d382c","#b2a283","#4f5144"],"group":"Sbadu"},{"id":"s213","a":1.277,"palette":["#382f27","#a1a8a1","#b2b2a7","#acaea5","#807859"],"group":"Sbadu"},{"id":"s215","a":1.511,"palette":["#0c2c30","#0f4b5c","#d5cdbc","#3b5d3b","#0e414f"],"group":"Sbadu"},{"id":"s217","a":0.803,"palette":["#3d3d3b","#ad7059","#f2eccc","#9ba37e","#e1ae7f"],"group":"Sbadu"},{"id":"s221","a":1.777,"palette":["#12181a","#678b8d","#32312d","#0e302f","#809d9a"],"group":"Sbadu"},{"id":"s226","a":0.843,"palette":["#cca45c","#55271a","#a82318","#a33a25","#cfa965"],"group":"Sbadu"},{"id":"s227","a":1.357,"palette":["#7b9d9e","#425e54","#97b1b1","#afbab2","#c4cabc"],"group":"Sbadu"},{"id":"s228","a":0.863,"palette":["#322522","#c5cdd2","#d0d0d5","#d0d2d5","#9b8980"],"group":"Sbadu"},{"id":"s230","a":1.775,"palette":["#3b6837","#1f4228","#4e7b41","#789d6a","#628852"],"group":"Sbadu"}];

  window.NeededTemplates = {
    samples: SAMPLES, samplePick: 'Lexus',
    list: [].concat(noir, gallery, anthem, system, frame, soft, signal, reel, vogue),
    palettes: [
      ['Pink & purple', { dark: '#1c1030', light: '#fbe3ee', accent: '#e0245e', tint: '#7b3fa0' }],
      ['Red & black', { dark: '#0a0605', light: '#f5e9e0', accent: '#c4161c', tint: '#6b0f12' }],
      ['Warm sun', { dark: '#2a1a0a', light: '#fff1d6', accent: '#f5a700', tint: '#e0531f' }],
      ['Ocean', { dark: '#0e2a3b', light: '#eef4f6', accent: '#1f5fbf', tint: '#9ad0e0' }],
      ['Forest', { dark: '#1d2a22', light: '#ece6d8', accent: '#6f8f5a', tint: '#c9b27c' }],
      ['Mono', { dark: '#0b0b0b', light: '#f2f0ec', accent: '#8a8784', tint: '#d9d5cf' }],
    ],
  };
})();
