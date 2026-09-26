/* Needed Design — treatment templates.
   Each template is a set of page designs drawn on a 1920 × 1080 page, in pixels. The editor turns them
   into ordinary pages: pictures, text boxes and shapes you can move, restyle and swap like any other.
   Colours are roles — bg, ink, accent, tint — so a palette can change the whole deck at once.
   Pictures are slots: the editor fills them from the vault with the stills that best fit the template. */
(function () {
  'use strict';
  // P: a picture slot. T: words. S: a shape (a block of colour, a rule, a circle).
  const P = (x, y, w, h, o) => Object.assign({ k: 'pic', x, y, w, h }, o || {});
  const T = (text, x, y, w, st) => Object.assign({ k: 'text', text, x, y, w }, st || {});
  const S = (shape, x, y, w, h, st) => Object.assign({ k: 'shape', shape, x, y, w, h }, st || {});
  // The biggest size (px) at which the longest word of a heading fits a width, for a font about `em` wide per letter.
  const fit = (t, w, max, em) => Math.min(max, Math.floor(w / (Math.max(...String(t).split(/\s+/).map(x => x.length), 1) * (em || 0.8))));
  const L = {
    xs: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
    s: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer posuere erat a ante venenatis dapibus posuere velit aliquet.',
    m: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean lacinia bibendum nulla sed consectetur. Maecenas sed diam eget risus varius blandit sit amet non magna. Nullam quis risus eget urna mollis ornare vel eu leo.',
    l: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean lacinia bibendum nulla sed consectetur. Maecenas sed diam eget risus varius blandit sit amet non magna. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Nullam quis risus eget urna mollis ornare vel eu leo. Vivamus sagittis lacus vel augue laoreet rutrum faucibus dolor auctor. Donec id elit non mi porta gravida at eget metus, etiam porta sem malesuada magna mollis euismod.',
    p2: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla vitae elit libero, a pharetra augue. Maecenas faucibus mollis interdum, cras mattis consectetur purus sit amet fermentum.\nDonec ullamcorper nulla non metus auctor fringilla. Vestibulum id ligula porta felis euismod semper, sed posuere consectetur est at lobortis.',
    p3: 'Lorem ipsum dolor sit amet is a film that unfolds within an electric atmosphere, combining the energy of the place with a playful narrative that echoes the song.\nAt the core of this project, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.\nThe story deepens as duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident.',
    line: 'A line that sets the tone — lorem ipsum dolor sit amet, spinning a web of intrigue with every move.',
  };

  /* ------------------------------------------------------------------ 01 Moody — after “Calm Is a Weapon” */
  const moody = (() => {
    const F = 'Inter Tight';
    const head = (t, x, y, w, al) => T(t, x, y, w, { font: F, size: 30, weight: 800, upper: true, leading: 1.13, align: al || 'left', c: 'ink' });
    const body = (t, x, y, w, sz) => T(t, x, y, w, { font: F, size: sz || 19, weight: 400, leading: 1.26, align: 'justify', hyph: true, c: 'ink' });
    const mark = c => T(c.client, 44, 1022, 400, { font: F, size: 17, weight: 800, italic: true, upper: true, c: 'ink' });
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080, { mono: true }),
        T(c.talent, 330, 590, 600, { font: F, size: 26, weight: 800, italic: true, upper: true, c: '#ffffff' }),
        T(c.title, 990, 590, 600, { font: F, size: 26, weight: 800, italic: true, align: 'right', c: '#ffffff' }),
        T(c.director, 1276, 1030, 600, { font: F, size: 15, weight: 800, upper: true, tracking: 0.02, align: 'right', c: '#ffffff' })] }),
      statement: c => ({ items: [P(640, 0, 1280, 1080, { mono: true }), S('rect', 640, 0, 560, 1080, { fill: 'bg', fadeTo: 'right', fadeAt: 0 }),
        T('A LINE THAT\nSETS THE\nTONE.', 80, 404, 320, { font: F, size: 30, weight: 800, leading: 1.13, c: 'ink' }),
        body(L.m, 232, 472, 340, 17), mark(c)] }),
      section: (c, h) => ({ items: [P(0, 0, 1180, 612, { mono: true, dim: 0.15 }), S('rect', 640, 0, 540, 612, { fill: 'bg', fadeTo: 'left', fadeAt: 0 }),
        P(0, 622, 950, 458, { mono: true }), P(960, 622, 960, 458, { dim: 0.35 }),
        head(h, 1014, 176, 830, 'right'), body(L.l, 1014, 222, 830, 20), mark(c)] }),
      grid: c => ({ items: [P(0, 0, 636, 506, { mono: true }), P(646, 0, 628, 506, { mono: true }), P(1284, 0, 636, 506, { mono: true }),
        P(0, 516, 440, 564, { mono: true }), P(450, 516, 840, 564, { mono: true }), P(1300, 516, 620, 564, { mono: true }), mark(c)] }),
      twocol: (c, h) => ({ items: [P(0, 0, 1920, 1080, { mono: true, dim: 0.65 }),
        head(h, 480, 430, 960, 'center'), body(L.m, 606, 480, 344, 18), body(L.m, 970, 480, 344, 18), mark(c)] }),
      story: (c, h) => ({ items: [P(0, 0, 1920, 1080, { mono: true, dim: 0.2 }), head(h, 1140, 250, 400), mark(c)] }),
      mosaic: (c, h) => ({ items: [P(0, 0, 640, 500, { mono: true }), P(650, 0, 620, 500, { mono: true }), P(1280, 0, 640, 500, { mono: true }),
        P(0, 510, 640, 570, { mono: true }), S('rect', 650, 510, 620, 570, { fill: '#1a1a1a' }), P(1280, 510, 640, 570, { mono: true }),
        head(h, 694, 560, 540), body(L.m, 694, 610, 530, 20), mark(c)] }),
      right: (c, h) => ({ items: [P(0, 0, 1080, 1080, { mono: true }), head(h, 1180, 380, 600), body(L.m, 1180, 430, 560, 20), mark(c)] }),
      close: c => ({ items: [P(0, 0, 1920, 1080, { mono: true, dim: 0.5 }),
        T('THANK YOU', 560, 516, 800, { font: F, size: 26, weight: 800, tracking: 0.5, align: 'center', c: 'ink' }),
        T(c.title.toUpperCase() + ' · ' + c.year, 560, 564, 800, { font: F, size: 15, tracking: 0.08, align: 'center', c: 'accent' }), mark(c)] }),
    };
    return { id: 'moody', name: 'Moody', after: 'Calm Is a Weapon', feel: 'Black pages, grainy black-and-white stills, small type set in justified blocks.',
      pal: { bg: '#000000', ink: '#f4f2ee', accent: '#9a9793', tint: '#1a1a1a' }, dark: true,
      want: { lum: 0.22, sat: null, hues: [], mono: true },
      runner: { font: F, size: 15, style: 'page' },
      order: [['cover'], ['statement'], ['section', 'Look & feel'], ['grid'], ['twocol', 'Production design'], ['story', 'Story'], ['right', 'Casting'], ['mosaic', 'Camera & movement'], ['section', 'Wardrobe'], ['grid'], ['twocol', 'Edit & sound'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 02 Heat — after “Most Wanted” */
  const heat = (() => {
    const F = 'Inter Tight', X = 'Anton', Q = 'Instrument Serif';
    const tall = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: Q, size: sz, upper: true, tall: 1.45, leading: 0.86, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz) => T(t, x, y, w, { font: F, size: sz || 22, leading: 1.32, align: 'justify', hyph: true, para: 0.8, c: 'ink' });
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080, { dim: 0.5 }),
        T(c.talent, 360, 92, 1200, { font: X, size: 96, tracking: 0.06, align: 'center', outline: 1.6, c: 'ink' }),
        T(c.title, 70, 200, 1780, { font: X, size: 330, leading: 0.86, align: 'center', upper: true, depth: 7, c: 'accent' }),
        T('A TREATMENT BY', 1250, 930, 600, { font: F, size: 11, tracking: 0.08, align: 'right', c: 'ink' }),
        T(c.director, 1250, 950, 600, { font: F, size: 26, weight: 700, upper: true, align: 'right', c: 'ink' })] }),
      statement: c => ({ items: [P(0, 0, 1920, 1080), tall(L.line, 1240, 300, 590, 64, { align: 'justify', lastJustify: true })] }),
      intro: (c, h) => ({ items: [P(720, 0, 1200, 1080), S('rect', 0, 0, 1180, 1080, { fill: 'accent', fadeTo: 'right', fadeAt: 0.78, op: 0.92 }),
        tall(h, 62, 270, 934, 72, { align: 'right' }), body(L.p3, 62, 402, 934)] }),
      word: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.38 }), T(h, 0, 180, 1920, { font: X, size: fit(h, 1780, 330, 0.46), upper: true, align: 'center', depth: 7, op: 0.92, c: 'accent' })] }),
      mosaic: (c, h) => ({ items: [P(18, 18, 800, 392), P(832, 18, 1070, 392), P(18, 426, 1150, 636),
        tall(h, 1260, 470, 600, 64), body(L.m, 1260, 612, 580)] }),
      story: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.3 }), S('rect', 0, 520, 1920, 560, { fill: 'bg', fadeTo: 'top', fadeAt: 0.2 }),
        tall(h, 64, 700, 1200, 76), body(L.l, 64, 822, 1792)] }),
      quote: c => ({ items: [P(0, 0, 900, 1080), tall(L.line.toUpperCase(), 1080, 380, 720, 60, { align: 'center' })] }),
      perf: (c, h) => ({ items: [P(44, 76, 410, 500), P(500, 0, 1420, 610), P(0, 640, 940, 440),
        tall(h, 560, 470, 800, 64), body(L.s, 1210, 810, 650)] }),
      close: c => ({ items: [P(0, 0, 1920, 1080, { dim: 0.45 }), T('THANK YOU', 0, 330, 1920, { font: X, size: 300, align: 'center', depth: 7, c: 'accent' }),
        T(c.director, 0, 760, 1920, { font: F, size: 22, weight: 700, upper: true, tracking: 0.1, align: 'center', c: 'ink' })] }),
    };
    return { id: 'heat', name: 'Heat', after: 'Most Wanted', feel: 'Red on black. A towering 3D title, tall condensed capitals for statements, stills to the edge.',
      pal: { bg: '#070404', ink: '#f6efe9', accent: '#e3231a', tint: '#6e0c08' }, dark: true,
      want: { lum: 0.3, sat: 0.55, hues: ['red', 'orange', 'pink', 'purple', 'brown'] },
      runner: { font: F, size: 14, style: 'pagepad' },
      order: [['cover'], ['statement'], ['intro', 'Introduction'], ['word', 'Choreography'], ['mosaic', 'Look & feel'], ['story', 'Story'], ['quote'], ['perf', 'Performance'], ['intro', 'Wardrobe'], ['mosaic', 'Locations'], ['word', 'Energy'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 03 Road — after “Juicy” */
  const road = (() => {
    const F = 'Inter Tight', B = 'Barlow';
    const tag = (c, x, y, st) => T(c.short, x, y, 104, Object.assign({ font: B, size: 19, weight: 500, align: 'center', fill: 'accent', c: '#ffffff', leading: 3.9 }, st || {}));
    const bar = (t, x, y, w, al) => T(t, x, y, w, { font: B, size: 24, weight: 500, align: al || 'center', fill: 'ink', c: '#ffffff', leading: 1.9, tracking: 0.02 });
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 18, leading: 1.28, align: 'justify', hyph: true, para: 1, c: '#ffffff' }, st || {}));
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080), tag(c, 1004, 440),
        T(c.director.split(' ')[0] || c.director, 700, 522, 294, { font: B, size: 24, weight: 500, upper: true, align: 'right', c: '#ffffff' }),
        T(c.director.split(' ').slice(1).join(' '), 972, 552, 400, { font: B, size: 24, weight: 500, upper: true, c: '#ffffff' }),
        T(c.director, 1276, 1030, 600, { font: F, size: 14, weight: 800, upper: true, align: 'right', c: '#ffffff' })] }),
      open: c => ({ items: [P(0, 0, 1920, 1080), bar('Some things burn slow, others get left behind  —  this one does both.', 1040, 734, 842),
        body('Lorem ipsum dolor sit amet?\nConsectetur adipiscing elit, sed do eiusmod tempor. Gone. Just like that.', 1040, 812, 256, 17, { font: B, align: 'left' }),
        body(L.s, 1333, 812, 256, 17, { font: B }), body('Duis aute irure dolor in reprehenderit, but it is in the unravelling where it all starts to make sense.', 1626, 812, 256, 17, { font: B }), tag(c, 36, 962)] }),
      panel: c => ({ bg: '#000000', items: [P(0, 0, 900, 1080), S('rect', 0, 0, 900, 1080, { fill: 'ink', op: 0.35 }), P(960, 44, 912, 540), P(910, 640, 1010, 440),
        tag(c, 404, 244), body(L.p3, 306, 362, 290, 18)] }),
      look: (c, h) => ({ bg: 'tint', items: [P(0, 0, 700, 504), P(710, 0, 580, 504), P(1300, 0, 620, 504), P(0, 514, 700, 566), P(1300, 514, 620, 566),
        bar(h.toUpperCase(), 710, 514, 580), body(L.p2, 744, 606, 512, 18, { c: 'ink' }), tag(c, 36, 962)] }),
      edit: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.28 }), bar(h.toUpperCase(), 1380, 64, 500, 'left'),
        body('The edit leans into this — dream logic over time logic.\nThings loop, return, echo. It is not clean. It is felt.', 1402, 140, 460, 18, { align: 'left', para: 0.4 }),
        body(L.p2, 1400, 740, 460, 18), tag(c, 36, 962)] }),
      story: (c, h) => ({ items: [P(0, 0, 1920, 1080), T(h.toUpperCase(), 1010, 500, 96, { font: B, size: 22, weight: 500, align: 'center', fill: 'ink', c: '#ffffff', leading: 3.4 }),
        body(L.p3, 1500, 280, 340, 17, { font: B, tracking: 0.02 }), tag(c, 36, 962)] }),
      trio: (c, h) => ({ bg: 'bg', items: [P(60, 150, 580, 700), P(670, 150, 580, 700), P(1280, 150, 580, 700), bar(h.toUpperCase(), 60, 64, 580, 'left'),
        body(L.xs, 60, 880, 580, 16, { align: 'left' }), body(L.xs, 670, 880, 580, 16, { align: 'left' }), body(L.xs, 1280, 880, 580, 16, { align: 'left' }), tag(c, 36, 962)] }),
      close: c => ({ items: [P(0, 0, 1920, 1080, { dim: 0.3 }), bar('THANK YOU', 810, 500, 300), tag(c, 36, 962)] }),
    };
    return { id: 'road', name: 'Road', after: 'Juicy', feel: 'Warm film stills, a blue title tile on every page, navy label bars and small text in narrow columns.',
      pal: { bg: '#0c1620', ink: '#0b3a78', accent: '#0a72cf', tint: '#c8f1ef' }, dark: true,
      want: { lum: 0.4, sat: 0.4, hues: ['orange', 'yellow', 'brown', 'blue', 'teal'] },
      runner: { font: F, size: 14, style: 'pagepad' },
      order: [['cover'], ['open'], ['panel'], ['look', 'Look and feel'], ['edit', 'Edit'], ['story', 'Story'], ['trio', 'Locations'], ['look', 'Wardrobe'], ['edit', 'Sound'], ['trio', 'Casting'], ['panel'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 04 Swiss — after “Where East Meets West” */
  const swiss = (() => {
    const K = 'Archivo Black', F = 'Inter Tight', M = 'Merriweather';
    const big = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: K, size: sz, leading: 0.86, tracking: -0.04, c: 'ink' }, st || {}));
    const num = (n, x, y, sz, st) => T(n, x, y, 300, Object.assign({ font: K, size: sz || 64, leading: 0.9, tracking: -0.04, c: 'accent' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: M, size: sz || 18, leading: 1.5, align: 'justify', hyph: true, para: 0.8, c: 'ink' }, st || {}));
    const side = (t, x, y) => T(t, x, y, 420, { font: F, size: 18, weight: 500, tracking: 0.3, upper: true, rot: 'down', c: 'accent' });
    const meta = (c, x, y, col) => [S('rect', x, y, 600, 46, { fill: 'none', border: col, radius: 10 }),
      T('DIRECTOR\n' + c.director.toUpperCase(), x + 14, y + 7, 180, { font: F, size: 12, weight: 700, leading: 1.1, c: col }),
      T('PROJECT\n' + c.title.toUpperCase(), x + 214, y + 7, 200, { font: F, size: 12, weight: 700, leading: 1.1, c: col }),
      T('VERSION\n' + c.month, x + 434, y + 7, 160, { font: F, size: 12, weight: 700, leading: 1.1, c: col })];
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080, { dim: 0.1 }),
        T(c.title.toUpperCase(), 160, 360, 1600, { font: F, size: 104, weight: 300, tracking: 0.02, align: 'center', c: '#ffffff' }),
        T('TREATMENT BY ' + c.director.toUpperCase(), 660, 600, 600, { font: F, size: 20, weight: 500, tracking: 0.12, align: 'center', c: '#ffffff' }),
        T('This document may contain confidential information. If you are not the intended recipient please notify the sender and delete it.', 160, 1040, 1600, { font: F, size: 9, align: 'center', c: '#ffffff' })] }),
      hook: (c, h, n) => ({ bg: '#000000', items: [P(0, 0, 1920, 1080, { dim: 0.2 }), ...meta(c, 560, 286, '#ffffff'), num(n, 206, 346, 68),
        big(h.toUpperCase(), 556, 346, 1100, 250, { c: '#ffffff' }),
        T('At the intersection of two worlds, we are creating a space for expression —', 1400, 352, 470, { font: M, size: 28, weight: 700, italic: true, leading: 1.05, c: '#ffffff' }),
        body(L.m, 1470, 480, 400, 15, { c: '#ffffff' })] }),
      intro: (c, h, n) => ({ items: [P(0, 0, 1920, 1080), num(n, 40, 24, 56), T(c.title.toUpperCase(), 760, 36, 400, { font: K, size: 28, align: 'center', c: '#ffffff' }),
        S('rect', 1170, 110, 700, 470, { fill: '#ffffff', op: 0.88 }), body(L.l, 1210, 150, 620, 18, { c: '#141414' }), big(h.toUpperCase(), 20, 860, 3000, 250, { c: '#ffffff' })] }),
      look: (c, h, n) => ({ bg: '#000000', items: [S('rect', 0, 0, 660, 540, { fill: '#ffffff' }), big(h.toUpperCase().replace(' & ', '\n&\n'), 30, 30, 620, fit(h, 600, 150, 0.8), { leading: 0.84 }),
        P(670, 0, 610, 540), P(1290, 0, 630, 540), P(0, 550, 660, 530), P(670, 550, 610, 530),
        num(n, 1700, 580, 56, { c: '#ffffff', align: 'right', w: 160 }), body(L.m, 1330, 660, 540, 17, { c: '#ffffff' })] }),
      set: (c, h, n) => ({ bg: '#ffffff', items: [P(0, 0, 380, 480), P(390, 0, 830, 480), P(0, 490, 1220, 590),
        body(L.m, 1290, 70, 580, 17, { c: '#141414' }), big(h.toUpperCase().replace(' ', '\n'), 1250, 290, 620, fit(h, 610, 150, 0.8), { c: 'accent', align: 'right' }),
        body(L.l, 1290, 590, 560, 17, { c: '#141414' }), side(h, 1880, 580), num(n, 40, 24, 56, { c: '#ffffff' })] }),
      edit: (c, h) => ({ bg: '#ffffff', items: [P(0, 0, 980, 1080), big('THE', 1150, 190, 300, 70, { c: '#141414' }), big(h.toUpperCase(), 1150, 260, 700, fit(h, 680, 210, 0.8), { c: '#141414' }),
        side(h, 1780, 210), body(L.l, 1150, 500, 700, 17, { c: '#141414' })] }),
      sound: (c, h, n) => ({ bg: '#000000', items: [P(0, 0, 1330, 1080), S('rect', 1330, 0, 590, 1080, { fill: 'accent' }), P(1380, 610, 490, 380),
        ...meta(c, 250, 520, '#ffffff'), num(n, 96, 590, 56), big(h.toUpperCase(), 246, 580, 1060, fit(h, 1040, 200, 0.8), { c: '#ffffff' }),
        body(L.m, 250, 800, 960, 16, { c: '#ffffff' }), body(L.l, 1380, 70, 490, 15, { c: '#ffffff' })] }),
      grid: c => ({ bg: '#ffffff', items: [P(0, 0, 960, 540), P(970, 0, 950, 540), P(0, 550, 640, 530), P(650, 550, 620, 530), P(1280, 550, 640, 530)] }),
      close: (c, h, n) => ({ bg: '#ffffff', items: [big('THANK\nYOU', 80, 560, 1200, 230, { c: '#141414' }), num(n, 80, 420, 68), side(c.title, 1840, 80), P(1300, 0, 620, 1080)] }),
    };
    return { id: 'swiss', name: 'Swiss', after: 'Where East Meets West', feel: 'White and black pages, huge black grotesk, a red number for each section, a serif for reading.',
      pal: { bg: '#ffffff', ink: '#0b0b0b', accent: '#e2231a', tint: '#f39c2b' }, dark: false,
      want: { lum: 0.45, sat: 0.2, hues: ['grey', 'blue', 'teal', 'green', 'white'] },
      runner: { font: F, size: 12, style: 'pad' },
      order: [['cover'], ['hook', 'Hook'], ['intro', 'Introduction'], ['look', 'Look & feel'], ['set', 'Set design'], ['grid'], ['edit', 'Edit'], ['sound', 'Sound'], ['look', 'Wardrobe'], ['set', 'Locations'], ['grid'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 05 Journey — after “Everyday Journey” */
  const journey = (() => {
    const I = 'Italiana', F = 'Inter Tight';
    const disp = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: I, size: sz, upper: true, leading: 1, c: '#ffffff' }, st || {}));
    const bold = (t, x, y, w, sz) => T(t, x, y, w, { font: F, size: sz || 46, weight: 800, italic: true, upper: true, leading: 1.02, c: 'accent' });
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 18, leading: 1.22, align: 'justify', hyph: true, para: 1, c: '#ffffff' }, st || {}));
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080),
        disp(c.talent + '\n' + c.client, 440, 505, 470, 36, { align: 'right', leading: 1.1 }), disp(c.title, 944, 500, 900, 84, { c: 'accent' }),
        T(c.director, 660, 1034, 600, { font: F, size: 17, weight: 800, upper: true, align: 'center', c: '#ffffff' })] }),
      journey: (c, h) => ({ bg: '#000000', items: [P(0, 90, 1920, 900), disp(h, 1310, 340, 560, 48, { tracking: 0.02 }), body(L.l, 1316, 410, 490, 17, { tracking: 0.01 })] }),
      look: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.3 }), T('LOOK', 620, 470, 460, { font: I, size: 132, c: 'accent', leading: 1 }), T('&', 1090, 440, 140, { font: I, size: 132, c: '#1a9a3c', leading: 1 }),
        T('FEEL', 1040, 570, 400, { font: I, size: 132, c: '#d9261c', leading: 1 }), body(L.l, 660, 600, 380, 16)] }),
      cine: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.15 }), disp(h, 420, 440, 900, 58, { align: 'center' }), body(L.p2, 420, 520, 640, 17)] }),
      grid: c => ({ items: [P(0, 0, 956, 536), P(964, 0, 956, 536), P(0, 544, 956, 536), P(964, 544, 956, 536)] }),
      shift: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.1 }), bold(h, 1280, 360, 560, 50), disp('A new chapter', 1420, 420, 480, 50, { c: 'accent' }), body(L.m, 1440, 490, 400, 16)] }),
      split: (c, h) => ({ bg: '#000000', items: [P(0, 0, 1170, 1080, { dim: 0.62 }), P(1188, 18, 714, 1044), bold(h, 180, 360, 700, 46), body(L.p2, 180, 470, 440, 17, { c: 'accent' }), body(L.m, 640, 470, 440, 17, { c: 'accent' })] }),
      moment: (c, h) => ({ bg: '#000000', items: [P(820, 0, 1100, 1080), S('rect', 820, 0, 500, 1080, { fill: '#000000', fadeTo: 'right', fadeAt: 0 }), bold(h.replace(' ', '\n'), 150, 440, 560, 52), body(L.m, 300, 580, 420, 16, { c: 'accent' })] }),
      close: c => ({ items: [P(0, 0, 1920, 1080, { dim: 0.25 }), disp('Thank you', 460, 490, 1000, 84, { align: 'center', c: 'accent' }),
        T(c.director, 660, 610, 600, { font: F, size: 17, weight: 800, upper: true, align: 'center', c: '#ffffff' })] }),
    };
    return { id: 'journey', name: 'Journey', after: 'Everyday Journey', feel: 'Warm, saturated stills, a thin display serif with bold italic headings, words in gold.',
      pal: { bg: '#120c06', ink: '#ffffff', accent: '#f2a900', tint: '#1a9a3c' }, dark: true,
      want: { lum: 0.45, sat: 0.6, hues: ['yellow', 'orange', 'red', 'green', 'blue', 'teal'] },
      runner: { font: F, size: 14, style: 'page' },
      order: [['cover'], ['journey', 'The journey'], ['look'], ['cine', 'Cinematography'], ['grid'], ['cine', 'Production design'], ['split', 'The process'], ['shift', 'The shift'], ['grid'], ['moment', 'Moments of reflection'], ['cine', 'Casting'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 06 Poppy — after “The Approach” */
  const poppy = (() => {
    const A = 'Archivo', F = 'Inter Tight';
    const hi = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: A, size: sz, weight: 900, italic: true, upper: true, leading: 0.82, tracking: -0.035, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 20, leading: 1.4, c: 'ink' }, st || {}));
    const lab = (t, x, y, w, st) => T(t, x, y, w, Object.assign({ font: F, size: 14, weight: 700, upper: true, tracking: 0.12, c: 'ink' }, st || {}));
    const rule = (x, y, w) => S('line', x, y, w, 2, { fill: 'ink', lw: 1.5 });
    const D = {
      cover: c => ({ runner: false, items: [P(1290, 56, 574, 968), hi(c.title, 50, 250, 1200, 190), rule(56, 900, 1180),
        lab(c.client, 56, 924, 400), lab('DIR. ' + c.director, 456, 924, 500), lab(c.year, 1036, 924, 200, { align: 'right' })] }),
      approach: (c, h, n) => ({ items: [hi('THE', 44, 110, 600, 230), P(640, 80, 450, 300), P(1110, 80, 760, 300), hi(h.replace(/^the /i, ''), 44, 420, 1860, 230),
        rule(56, 740, 1808), lab(n + ' — ' + h, 56, 766, 500), body(L.m, 600, 766, 820, 20)] }),
      style: (c, h) => ({ items: [P(56, 100, 680, 360), hi(h.replace(' ', '\n'), 784, 120, 1000, 130),
        S('rect', 0, 700, 1920, 380, { fill: 'ink' }),
        lab('LIGHT', 56, 760, 500, { c: 'bg' }), body(L.s, 56, 800, 540, 19, { c: 'bg' }),
        lab('CAMERA', 690, 760, 500, { c: 'bg' }), body(L.s, 690, 800, 540, 19, { c: 'bg' }),
        lab('COLOUR', 1324, 760, 500, { c: 'bg' }), body(L.s, 1324, 800, 540, 19, { c: 'bg' })] }),
      band: (c, h) => ({ bg: 'accent', items: [P(0, 0, 960, 1080), P(960, 0, 960, 1080), T(h.toUpperCase(), 610, 480, 700, { font: A, size: 80, weight: 900, italic: true, align: 'center', fill: 'bg', c: 'ink', leading: 1.2, tracking: -0.02 })] }),
      trio: (c, h) => ({ items: [hi(h, 56, 80, 1200, 120), rule(56, 230, 1808),
        P(56, 270, 580, 620), P(670, 270, 580, 620), P(1284, 270, 580, 620),
        lab('01', 56, 912, 60), body(L.xs, 120, 910, 500, 17), lab('02', 670, 912, 60), body(L.xs, 734, 910, 500, 17), lab('03', 1284, 912, 60), body(L.xs, 1348, 910, 500, 17)] }),
      full: (c, h) => ({ items: [P(0, 0, 1920, 1080), hi(h, 56, 850, 1600, 150, { c: 'bg' })] }),
      text: (c, h, n) => ({ items: [lab(n + ' — ' + h, 56, 120, 600), hi(h, 56, 160, 800, 150), body(L.p2, 1000, 170, 860, 24), rule(56, 900, 1808), P(1000, 560, 860, 300)] }),
      close: c => ({ bg: 'accent', items: [hi('THANK\nYOU', 56, 380, 1300, 260, { c: 'bg' }), P(1300, 56, 564, 968), lab('DIR. ' + c.director, 56, 980, 600, { c: 'bg' })] }),
    };
    return { id: 'poppy', name: 'Poppy', after: 'The Approach', feel: 'Peach and black, heavy italic capitals stacked with pictures, bold black bands and hairline rules.',
      pal: { bg: '#f6d3c4', ink: '#0b0b0b', accent: '#e0245e', tint: '#ffffff' }, dark: false,
      want: { lum: 0.55, sat: 0.45, hues: ['pink', 'orange', 'red', 'yellow', 'white'] },
      runner: { font: F, size: 13, style: 'pad' },
      order: [['cover'], ['approach', 'The approach'], ['style', 'Visual style'], ['band', 'Casting'], ['trio', 'Wardrobe'], ['full', 'Story'], ['text', 'Tone'], ['trio', 'Locations'], ['band', 'Light'], ['style', 'Camera'], ['full', 'Music'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 07 Electric — after “Bright” */
  const electric = (() => {
    const R = 'Rubik Mono One', F = 'Inter Tight';
    const out = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: R, size: sz, leading: 0.95, outline: 2, c: 'ink' }, st || {}));
    const solid = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: R, size: sz, leading: 0.95, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 20, weight: 500, leading: 1.4, c: 'ink' }, st || {}));
    const pill = (t, x, y, w) => T(t, x, y, w, { font: F, size: 18, weight: 800, upper: true, tracking: 0.1, fill: 'accent', c: 'ink', leading: 1.6, align: 'center' });
    const D = {
      cover: c => ({ runner: false, bg: 'accent', items: [S('rect', 0, 0, 1920, 1080, { fill: 'bg', fadeTo: 'bottom', fadeAt: 0 }), P(0, 0, 1920, 1080, { op: 0.72 }),
        out('HELLO', 48, 120, 1800, 250, { outline: 3 }), solid(c.title, 56, 820, 1500, 56), body(c.client.toUpperCase() + ' · DIR. ' + c.director.toUpperCase(), 58, 910, 1200, 20, { weight: 700, tracking: 0.1 })] }),
      story: (c, h) => ({ items: [P(0, 0, 880, 1080), out(h.replace(' ', '\n'), 930, 130, 900, 96), body(L.m, 930, 420, 860, 22), pill('TONE: LOUD, WARM', 930, 640, 360)] }),
      insets: (c, h) => ({ items: [P(0, 0, 1920, 1080), P(1400, 80, 400, 270, { border: 'bg' }), P(1180, 400, 400, 270, { border: 'bg' }), out(h, 56, 880, 1400, 84, { c: '#ffffff' })] }),
      palette: (c, h) => ({ items: [solid(h, 56, 80, 1000, 80), S('rect', 56, 260, 430, 430, { fill: 'bg', border: 'ink' }), S('rect', 506, 260, 430, 430, { fill: 'accent' }), S('rect', 956, 260, 430, 430, { fill: 'ink' }),
        P(1406, 260, 458, 430), body('Background', 56, 710, 430, 16, { weight: 800 }), body('Accent', 506, 710, 430, 16, { weight: 800 }), body('Words', 956, 710, 430, 16, { weight: 800 }), body(L.s, 56, 820, 1300, 22)] }),
      stack: (c, h) => ({ bg: 'accent', items: [out(h, 56, 70, 1808, 190, { c: 'bg' }), solid(h, 56, 290, 1808, 190, { c: 'bg' }), out(h, 56, 510, 1808, 190, { c: 'bg' }), P(1180, 740, 684, 300), body(L.s, 56, 780, 900, 22, { c: 'bg' })] }),
      duo: (c, h) => ({ items: [P(56, 56, 890, 968, { border: 'accent' }), P(974, 56, 890, 600), solid(h, 974, 700, 890, 70), body(L.m, 974, 800, 860, 20)] }),
      close: c => ({ runner: false, items: [S('circle', 460, -40, 1000, 1000, { fill: 'accent' }), solid('BRIGHT', 0, 330, 1920, 190, { align: 'center' }), out('THANKS', 0, 540, 1920, 190, { align: 'center' })] }),
    };
    return { id: 'electric', name: 'Electric', after: 'Bright', feel: 'Saturated colour, outlined display letters, framed pictures laid over pictures.',
      pal: { bg: '#ffd400', ink: '#120a0a', accent: '#ff3b1f', tint: '#7b3fa0' }, dark: false,
      want: { lum: 0.55, sat: 0.75, hues: ['yellow', 'orange', 'red', 'pink', 'purple', 'blue'] },
      runner: { font: F, size: 13, style: 'pad' },
      order: [['cover'], ['story', 'The story'], ['insets', 'Energy'], ['palette', 'Colour'], ['duo', 'Casting'], ['stack', 'Motion'], ['insets', 'Locations'], ['story', 'The look'], ['duo', 'Wardrobe'], ['palette', 'Light'], ['stack', 'Music'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 08 Kinetic — after “Visual Style / Reset” */
  const kinetic = (() => {
    const N = 'Anton', F = 'Inter Tight';
    const big = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: N, size: sz, leading: 0.92, upper: true, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 19, leading: 1.45, c: 'ink' }, st || {}));
    const side = (t, x, y, st) => T(t, x, y, 700, Object.assign({ font: F, size: 16, weight: 700, upper: true, tracking: 0.2, rot: 'up', c: 'ink' }, st || {}));
    const frame = (x, y, w, h) => P(x, y, w, h, { border: 'accent', bw: 6, radius: 22 });
    const D = {
      cover: c => { const w = String(c.title).trim().split(/\s+/), a = w.length > 1 ? w[0] : c.title.slice(0, Math.ceil(c.title.length / 2)), b = w.length > 1 ? w.slice(1).join(' ') : c.title.slice(Math.ceil(c.title.length / 2));
        const sz = Math.min(360, Math.round(1500 / Math.max(4, (a + b).length * 0.5)));
        return { runner: false, items: [big(a, 40, 250, 800, sz, { align: 'right' }), frame(860, 250, 240, sz * 1.02), big(b, 1120, 250, 800, sz),
        body(c.client.toUpperCase() + ' · DIR. ' + c.director.toUpperCase(), 56, 1004, 1200, 18, { weight: 700, tracking: 0.12 }), T(c.year, 1664, 1004, 200, { font: F, size: 18, weight: 700, align: 'right', c: 'accent' })] }; },
      style: (c, h, n) => ({ items: [P(112, 0, 860, 1080), frame(760, 460, 340, 300), side(c.director + ' · ' + c.title, 40, 340),
        big(h.replace(' ', '\n'), 1160, 100, 700, 110), body(L.m, 1160, 380, 640, 20), T(n, 1700, 980, 160, { font: N, size: 44, align: 'right', c: 'accent' })] }),
      move: (c, h) => ({ items: [P(0, 0, 1920, 1080), frame(1500, 72, 360, 240), frame(1390, 352, 280, 200), side(c.director + ' · ' + c.title, 40, 340, { c: '#ffffff' }), big(h, 112, 800, 1500, 190, { c: '#ffffff' })] }),
      word: (c, h) => ({ items: [big(h.slice(0, Math.ceil(h.length / 2)), 40, 300, 880, fit(h, 1600, 330, 0.5), { align: 'right' }), frame(930, 290, 260, 360), big(h.slice(Math.ceil(h.length / 2)), 1210, 300, 700, fit(h, 1600, 330, 0.5)), body(L.s, 1210, 820, 600, 20)] }),
      cast: (c, h) => ({ items: [big(h, 112, 70, 1200, 120), frame(112, 250, 540, 640), frame(690, 250, 540, 640), frame(1268, 250, 540, 640),
        T('01', 112, 910, 100, { font: N, size: 40, c: 'accent' }), body(L.xs, 190, 918, 440, 17), T('02', 690, 910, 100, { font: N, size: 40, c: 'accent' }), body(L.xs, 768, 918, 440, 17),
        T('03', 1268, 910, 100, { font: N, size: 40, c: 'accent' }), body(L.xs, 1346, 918, 440, 17), side(c.director + ' · ' + c.title, 40, 340)] }),
      split: (c, h) => ({ items: [P(960, 0, 960, 1080), big(h.replace(' ', '\n'), 112, 120, 800, 150), body(L.p2, 112, 560, 700, 20), frame(660, 700, 360, 280), side(c.director + ' · ' + c.title, 40, 340)] }),
      close: c => ({ bg: 'accent', items: [big('THANK YOU', 0, 420, 1920, 220, { align: 'center', leading: 1 }), side(c.director + ' · ' + c.title, 40, 340)] }),
    };
    return { id: 'kinetic', name: 'Kinetic', after: 'Visual Style / Reset', feel: 'Sport energy: tall condensed capitals, sideways labels, rounded frames breaking into the words.',
      pal: { bg: '#efe7e2', ink: '#141414', accent: '#ff5fa2', tint: '#ffffff' }, dark: false,
      want: { lum: 0.45, sat: 0.4, hues: ['blue', 'green', 'teal', 'orange', 'pink'] },
      runner: { font: F, size: 13, style: 'pad' },
      order: [['cover'], ['style', 'Visual style'], ['move', 'Movement'], ['word', 'Reset'], ['cast', 'Casting'], ['split', 'The idea'], ['move', 'Locations'], ['style', 'Camera'], ['cast', 'Wardrobe'], ['word', 'Speed'], ['split', 'Sound design'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 09 Editorial — after “Matcha Latte / Inspiration” */
  const editorial = (() => {
    const S1 = 'Instrument Serif', F = 'Inter Tight';
    const ser = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: S1, size: sz, leading: 0.95, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 19, leading: 1.6, c: 'ink' }, st || {}));
    const hair = (x, y, w, col) => S('line', x, y, w, 2, { fill: col || 'ink', lw: 1 });
    const mast = (c, n) => [hair(56, 72, 1808), T('ISSUE 01', 1664, 44, 200, { font: F, size: 13, tracking: 0.14, align: 'right', c: 'ink' })];
    const D = {
      cover: c => ({ runner: false, items: [...mast(c), T(c.director.toUpperCase() + ' · ' + c.title.toUpperCase(), 56, 44, 1200, { font: F, size: 13, tracking: 0.14, c: 'ink' }),
        P(1100, 130, 764, 880), ser(c.title, 56, 300, 1000, 190, { leading: 0.88 }), ser('a film for ' + c.client, 60, 700, 900, 44, { italic: true }),
        hair(56, 950, 900), body('Directed by ' + c.director + '. ' + c.month + '.', 56, 970, 900, 18)] }),
      band: (c, h) => ({ items: [S('rect', 0, 330, 1920, 460, { fill: 'accent' }), P(140, 200, 640, 640, { round: true }), ser(h, 900, 380, 900, 110), body(L.m, 904, 540, 760, 21)] }),
      three: (c, h) => ({ items: [P(56, 130, 560, 820), P(646, 130, 560, 560), ser(L.xs, 646, 720, 560, 30, { italic: true, leading: 1.1 }),
        ser(h, 1260, 130, 600, 80), hair(1262, 250, 80), body(L.l, 1262, 290, 600, 18)] }),
      contents: (c, h) => ({ items: [ser(h, 56, 110, 800, 110), body(L.s, 60, 280, 620, 20),
        ...['Introduction', 'Look & feel', 'Casting', 'Wardrobe', 'Locations', 'Camera', 'Sound'].flatMap((n, i) => [hair(900, 130 + i * 118, 964), ser(String(i + 1).padStart(2, '0'), 900, 150 + i * 118, 120, 50, { c: 'accent' }), ser(n, 1040, 150 + i * 118, 700, 50)]),
        hair(900, 956, 964)] }),
      quote: c => ({ items: [ser('“' + L.line + '”', 260, 300, 1400, 84, { italic: true, align: 'center', leading: 1.05 }), hair(900, 760, 120, 'accent'), body(c.director, 660, 790, 600, 16, { align: 'center', upper: true, tracking: 0.14 })] }),
      full: (c, h) => ({ items: [P(0, 0, 1920, 1080), S('rect', 56, 700, 700, 324, { fill: 'bg' }), ser(h, 96, 740, 620, 70), body(L.s, 96, 840, 620, 18)] }),
      pair: (c, h) => ({ items: [P(56, 130, 894, 894), P(970, 130, 894, 560), ser(h, 970, 730, 894, 70), body(L.m, 972, 830, 860, 18)] }),
      close: c => ({ items: [P(0, 0, 1920, 1080), S('circle', 740, 320, 440, 440, { fill: 'bg' }), ser('Thank you', 740, 490, 440, 70, { italic: true, align: 'center' })] }),
    };
    return { id: 'editorial', name: 'Editorial', after: 'Matcha Latte / Inspiration', feel: 'Cream paper, a classic serif, hairline rules and round crops — magazine calm.',
      pal: { bg: '#ebe8df', ink: '#23261f', accent: '#9fb59a', tint: '#ffffff' }, dark: false,
      want: { lum: 0.62, sat: 0.2, hues: ['green', 'white', 'grey', 'brown', 'yellow'] },
      runner: { font: F, size: 12, style: 'pad' },
      order: [['cover'], ['contents', 'Contents'], ['band', 'Inspiration'], ['three', 'Wardrobe'], ['quote'], ['full', 'Locations'], ['pair', 'Casting'], ['three', 'Light'], ['band', 'Colour'], ['full', 'Story'], ['pair', 'Camera'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 10 Grid — after “Business as Usual / Geometos” */
  const grid = (() => {
    const A = 'Archivo', F = 'Inter Tight';
    const wide = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: A, size: sz, weight: 300, stretch: 125, upper: true, tracking: 0.08, leading: 1, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: F, size: sz || 19, leading: 1.55, c: 'ink' }, st || {}));
    const hair = (x, y, w, col) => S('line', x, y, w, 2, { fill: col || 'ink', lw: 1 });
    const foot = (c, n) => [S('rect', 0, 1016, 1920, 64, { fill: 'ink' }), T(c.director.toUpperCase() + ' · ' + c.title.toUpperCase(), 56, 1038, 1200, { font: F, size: 15, tracking: 0.2, c: 'bg' }), T(n, 1664, 1038, 200, { font: F, size: 15, tracking: 0.2, align: 'right', c: 'bg' })];
    const D = {
      cover: (c, h, n) => ({ runner: false, items: [S('rect', 56, 56, 1808, 904, { fill: 'none', border: 'ink' }), wide(c.title.replace(' ', ' • '), 100, 420, 1720, 100, { align: 'center' }),
        body(c.client.toUpperCase() + ' · DIR. ' + c.director.toUpperCase(), 100, 580, 1720, 18, { align: 'center', tracking: 0.3 }), ...foot(c, n)] }),
      hi: (c, h, n) => ({ runner: false, items: [hair(56, 56, 880), wide('HI.', 56, 90, 880, 170), body(L.m, 56, 700, 600, 20), P(984, 56, 880, 904), ...foot(c, n)] }),
      narr: (c, h, n) => ({ runner: false, items: [P(56, 56, 1808, 500), hair(56, 600, 580), wide(h, 56, 626, 580, 46), hair(670, 600, 580), body(L.s, 670, 630, 560, 19), hair(1284, 600, 580, 'accent'), body(L.s, 1284, 630, 560, 19), ...foot(c, n)] }),
      index: (c, h, n) => ({ runner: false, items: [P(56, 56, 580, 800), P(670, 56, 580, 800), P(1284, 56, 580, 800),
        body('01 · ' + h.toUpperCase(), 56, 880, 580, 16, { tracking: 0.16 }), body('02 · CASTING', 670, 880, 580, 16, { tracking: 0.16 }), body('03 · WARDROBE', 1284, 880, 580, 16, { tracking: 0.16 }), ...foot(c, n)] }),
      table: (c, h, n) => ({ runner: false, items: [wide(h, 56, 70, 1200, 70), hair(56, 200, 1808),
        ...[['DAY', 'LOCATION', 'SCENES', 'CALL'], ['01', 'Lorem studio', 'Opening, performance', '07:00'], ['01', 'Ipsum street', 'Walk and talk', '15:30'], ['02', 'Dolor coast', 'The shift', '05:45'], ['02', 'Amet house', 'Reflection, close', '18:00']].flatMap((r, i) =>
          [hair(56, 290 + i * 130, 1808, i ? 'ink' : 'accent')].concat(r.map((v, j) => body(v, 56 + [0, 260, 900, 1600][j], 310 + i * 130, [240, 620, 680, 260][j], i ? 24 : 15, i ? {} : { tracking: 0.2 })))), ...foot(c, n)] }),
      full: (c, h, n) => ({ runner: false, items: [P(0, 0, 1920, 1016), S('rect', 56, 56, 620, 140, { fill: 'bg' }), wide(h, 86, 100, 580, 46), ...foot(c, n)] }),
      duo: (c, h, n) => ({ runner: false, items: [P(56, 56, 1180, 904), wide(h, 1284, 56, 580, 50), hair(1284, 150, 580), body(L.l, 1284, 180, 580, 18), ...foot(c, n)] }),
      close: (c, h, n) => ({ runner: false, items: [S('rect', 56, 56, 1808, 904, { fill: 'none', border: 'ink' }), wide('THANK • YOU', 100, 440, 1720, 100, { align: 'center' }), ...foot(c, n)] }),
    };
    return { id: 'grid', name: 'Grid', after: 'Business as Usual / Geometos', feel: 'Dark green and cream, light wide capitals, a strict grid and a running footer bar.',
      pal: { bg: '#ece6d8', ink: '#1d2a22', accent: '#c9b27c', tint: '#ffffff' }, dark: false,
      want: { lum: 0.5, sat: 0.3, hues: ['green', 'teal', 'brown', 'grey', 'blue'] },
      runner: null,
      order: [['cover'], ['hi'], ['narr', 'Narrative'], ['full', 'Location'], ['duo', 'Approach'], ['index', 'Places'], ['narr', 'Tone'], ['full', 'Light'], ['duo', 'Casting'], ['table', 'Schedule'], ['index', 'Looks'], ['close']], D };
  })();

  /* ------------------------------------------------------------------ 11 Monolith — after “Biohacker” */
  const monolith = (() => {
    const A = 'Archivo', M = 'Inter Tight';
    const wide = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: A, size: sz, weight: 800, stretch: 125, upper: true, leading: 0.92, c: 'ink' }, st || {}));
    const body = (t, x, y, w, sz, st) => T(t, x, y, w, Object.assign({ font: M, size: sz || 19, leading: 1.6, c: 'ink', op: 0.85 }, st || {}));
    const mono = (t, x, y, w, st) => T(t, x, y, w, Object.assign({ font: 'Courier Prime', size: 17, leading: 1.5, c: 'accent', upper: true }, st || {}));
    const D = {
      cover: c => ({ runner: false, items: [P(0, 0, 1920, 1080, { dim: 0.35 }), wide(c.title, 64, 760, 1100, 116), mono(c.client + '\n' + c.director + '\n' + c.year, 1500, 840, 356, { align: 'right', c: 'ink' })] }),
      prio: (c, h, n) => ({ items: [P(1120, 0, 800, 1080), mono(n + ' —', 64, 300, 400), wide(h, 64, 350, 900, 62), body(L.m, 64, 560, 620, 19)] }),
      three: (c, h) => ({ items: [P(64, 120, 588, 500), P(666, 120, 588, 500), P(1268, 120, 588, 500),
        wide('Space', 64, 660, 560, 26), body(L.xs, 64, 710, 520, 17), wide('Material', 666, 660, 560, 26), body(L.xs, 666, 710, 520, 17), wide('Light', 1268, 660, 560, 26), body(L.xs, 1268, 710, 520, 17)] }),
      glance: (c, h) => ({ items: [wide(h, 64, 120, 1000, 52), ...[['03', 'Locations'], ['02', 'Shoot days'], ['01', 'Film · 60s']].flatMap(([n, t], i) => [wide(n, 64 + i * 620, 400, 600, 260, { c: 'accent' }), mono(t, 70 + i * 620, 690, 520, { c: 'ink' })]), body(L.s, 64, 860, 900, 19)] }),
      full: (c, h) => ({ items: [P(0, 0, 1920, 1080, { dim: 0.15 }), mono(h, 64, 1000, 900, { c: '#ffffff' })] }),
      split: (c, h) => ({ items: [P(0, 0, 960, 1080), wide(h, 1040, 120, 820, 62), body(L.p2, 1040, 360, 760, 19), P(1040, 690, 820, 330)] }),
      close: c => ({ items: [P(0, 0, 1920, 1080, { dim: 0.55 }), wide('Thank\nyou.', 64, 700, 1200, 150), mono(c.director, 1500, 960, 356, { align: 'right', c: 'ink' })] }),
    };
    return { id: 'monolith', name: 'Monolith', after: 'Biohacker', feel: 'Dark and architectural: extra-wide heavy capitals, big quiet margins, one bright accent.',
      pal: { bg: '#111316', ink: '#eceae6', accent: '#d6ff3a', tint: '#23262b' }, dark: true,
      want: { lum: 0.28, sat: 0.2, hues: ['blue', 'grey', 'black', 'teal'] },
      runner: { font: 'Courier Prime', size: 14, style: 'pad' },
      order: [['cover'], ['prio', 'Our priorities'], ['three', 'The world'], ['full', 'Exterior · dusk'], ['glance', 'At a glance'], ['split', 'Architecture'], ['full', 'Interior · night'], ['three', 'Materials'], ['prio', 'The approach'], ['split', 'Light'], ['full', 'Final frame'], ['close']], D };
  })();

  window.NeededTemplates = {
    list: [moody, heat, road, swiss, journey, poppy, electric, kinetic, editorial, grid, monolith],
    // Palettes you can put on any template: dark, light, accent, tint.
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
