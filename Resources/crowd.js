// 오늘의 판 — the crowd (spec 6.25)
//
// The longer the music plays without a break, the more little people drop by: one 3-7 minutes in, then one every
// 3-5 minutes, up to 6. They walk around the turntable and the desk, sit on the plinth's edge swinging their feet,
// dance, headbang, breakdance, read, doze off, take phone calls, play together and run on the spinning record.
// When the music stops they go home one by one, every 30-60 seconds; whoever is still there when it starts again stays.
//
// index.html creates it with TodaysRecordCrowd(scene) and calls update(dt, now) and draw(L, C, now) every frame.
// `scene` gives read access to the page's state and drawing helpers (see makeCrowd in index.html).
// Without this file the page works as before, just without the crowd.
(() => {
  'use strict';

  window.TodaysRecordCrowd = function createCrowd(S) {
    const { layout, layoutKey, toScreen, armTip, phiOf, toHex, hex, css, mix, clamp, lerp, rand, easeInOut, easeOut, wander, rrect, disc, drawPix } = S.fn;
    const { TAU, TILT, SQUASH, ARM, R_IN, R_OUT, REST_PHI, PLINTH_T, RPS } = S.geo;
    let ctx = null;

    const MAX = 6;
    const PLINTH = { x0: -1.22, y0: -1.18, x1: 5.78, y1: 5.82 };   // in record radii, record-plane coordinates
    const crowd = { people: [], play: 0, idle: 0, nextAt: rand(180, 420), leaveAt: rand(30, 60), stopped: false, beat: 0, spots: null, spotsKey: '', hud: null, fx: [], prot: [], trackKey: '' };
    // Crowd Pace in the settings (1, 2, 5 or 10 times as fast); test copies can speed it up further
    const speed = () => (S.opts.crowdPace || 1) * ((S.NATIVE && S.NATIVE.crowdSpeed) || 1);

    // ---------- looks ----------
    const LOOKS = {
      skin: ['#F6D7C3', '#F1C6A3', '#E0AC87', '#C68A62', '#9A6644', '#7A4B32'],
      hair: ['#2B2320', '#2B2320', '#4A3326', '#7A4E2D', '#B5793F', '#E2C27A', '#C2553F', '#E79BB8', '#7C8CE0', '#EDEAE4'],
      styles: ['short', 'bob', 'long', 'pony', 'buns', 'curly', 'cap', 'beanie', 'spiky'],
      shirt: ['#F28C8C', '#F6C85F', '#7BC8A4', '#6FA8DC', '#B79CED', '#FFFFFF', '#F4A261', '#FF8FB1', '#5FC2C7'],
      pants: ['#3D5A80', '#26262A', '#B59E72', '#6B4E71', '#E9E2D0', '#4F7A5A', '#A8473F'],
      shoes: ['#FFF8F1', '#2A2527', '#E0443C', '#3A7BD5', '#F6C85F'],
      prop: ['#E0443C', '#3A7BD5', '#3FAF6A', '#F07A2A', '#8E5A9A', '#F6C85F'],
    };
    const pick = a => a[Math.floor(Math.random() * a.length)];
    const chance = p => Math.random() < p;

    // some shirts take the album's accent so the crowd feels part of the scene; none may vanish into the plinth or desk
    function shirtFor(C) {
      const far = c => [C.plinth, C.bg].every(o => Math.hypot(c[0] - o[0], c[1] - o[1], c[2] - o[2]) > 70);
      if (chance(0.35) && far(C.accent)) return toHex(C.accent);
      const ok = LOOKS.shirt.filter(h => far(hex(h)));
      return pick(ok.length ? ok : LOOKS.shirt);
    }

    function makeLook(C) {
      const style = pick(LOOKS.styles), r = Math.random();
      return {
        skin: pick(LOOKS.skin), hair: pick(LOOKS.hair), style, shirt: shirtFor(C),
        pants: pick(LOOKS.pants), shoes: pick(LOOKS.shoes), hat: pick(LOOKS.shirt), prop: pick(LOOKS.prop),
        acc: r < 0.16 ? 'glasses' : r < 0.3 ? 'phones' : r < 0.42 && ['long', 'bob', 'pony', 'buns'].includes(style) ? 'bow' : r < 0.52 ? 'scarf' : '',
        bag: chance(0.22), freckles: chance(0.2), scarf: pick(LOOKS.prop),
      };
    }

    // ---------- where people can be ----------
    function toPlane(L, sx, sy) {
      const dx = sx - L.cx, dy = sy - L.cy, c = Math.cos(TILT), s = Math.sin(TILT);
      return { x: (dx * c + dy * s) / L.R, y: ((-dx * s + dy * c) / SQUASH) / L.R };
    }
    const onPlinth = (q, m = 0) => q.x > PLINTH.x0 + m && q.y > PLINTH.y0 + m && q.x < PLINTH.x1 - m && q.y < PLINTH.y1 - m;
    const unitOf = L => clamp(L.R * 0.16, 26, 90) / 40 * 0.92;
    const toward = (L, p) => (L.cx > p.x ? 1 : -1);

    // A desk point covered by the plinth's side face: how far up the plinth's top edge is (0 if not on the side face).
    // Nobody stands there (walking across it, straight up the screen, already looks like climbing the side).
    function wallLift(L, x, y) {
      if (onPlinth(toPlane(L, x, y))) return 0;
      const t = PLINTH_T * L.R;
      for (let k = 2; k <= t + 2; k += 2) if (onPlinth(toPlane(L, x, y - k))) return k;
      return 0;
    }

    // Screen points nobody may stand in front of: knobs, lamps, the tonearm and its rest, the needle's path.
    function protectedPoints(L) {
      const R = L.R, pts = [], P = (x, y) => pts.push(toScreen(L, x * R, y * R));
      for (let a = 0.62; a <= 2.08; a += 0.06) { P(Math.cos(a) * 1.22, Math.sin(a) * 1.22); P(Math.cos(a) * 1.36, Math.sin(a) * 1.36); }
      for (let a = 0; a < TAU; a += 0.5) P(ARM.bx + Math.cos(a) * 0.14, ARM.by + Math.sin(a) * 0.14);
      const rest = armTip(REST_PHI);
      for (let t = -0.25; t <= 1; t += 0.125) P(ARM.bx + (rest.x - ARM.bx) * t, ARM.by + (rest.y - ARM.by) * t);
      for (let fr = R_IN; fr <= R_OUT + 0.01; fr += 0.08) { const t = armTip(phiOf(fr)); P(t.x, t.y); }
      return pts;
    }

    // kind: 'stand' (feet on the plinth or desk), 'edge' (sitting on the plinth's left edge, legs over the side),
    // 'run' (on the record itself)
    function spotOK(L, x, y, kind, u) {
      const q = toPlane(L, x, y), r = Math.hypot(q.x, q.y);
      if (kind === 'run' ? r > 0.95 : r < 1.16) return false;
      if (kind === 'stand' && !(onPlinth(q, 0.08) || !onPlinth(q, -0.1))) return false;   // not right on the edge
      if (kind === 'stand' && wallLift(L, x, y - 4 * u) > 0) return false;   // nor on (or just below) the side face
      const top = kind === 'edge' ? 29 * u : 35 * u, bot = kind === 'edge' ? 11 * u : 3 * u, half = 10 * u;
      const W = S.W, H = S.H, inset = S.inset;
      if (x - half < inset.left + 6 || x + half > W - inset.right - 6 || y - top < inset.top + 6 || y + bot > H - inset.bottom - 6) return false;
      const hb = crowd.hud;
      if (hb && x + half > hb.x - 10 && x - half < hb.x + hb.w + 10 && y - top < hb.y + hb.h + 10 && y + bot > hb.y - 10) return false;
      for (const p of crowd.prot) if (p.x > x - half - 6 && p.x < x + half + 6 && p.y > y - top - 6 && p.y < y + bot + 6) return false;
      return true;
    }

    // Free spots are worked out again whenever the layout changes (record position, screen size, insets, info text),
    // so with the record on the left, center or right everyone stands on whatever floor that layout shows.
    function spots(L) {
      const u = unitOf(L), inset = S.inset, hb = crowd.hud;
      const key = [layoutKey(L), inset.top, inset.bottom, inset.left, inset.right, hb ? Math.round(hb.h / 24) + ',' + Math.round(hb.x) : ''].join('|');
      if (crowd.spotsKey === key && crowd.spots) return crowd.spots;
      crowd.prot = protectedPoints(L);
      const list = [];
      for (let lx = -4; lx <= 4.5; lx += 0.1) for (let ly = -3.5; ly <= 3.5; ly += 0.1) {
        const s = toScreen(L, lx * L.R, ly * L.R);
        if (spotOK(L, s.x, s.y, 'stand', u)) list.push({ x: s.x, y: s.y, kind: 'stand' });
      }
      for (let ly = PLINTH.y0 + 0.12; ly <= 4; ly += 0.07) {
        const s = toScreen(L, PLINTH.x0 * L.R, ly * L.R);
        if (spotOK(L, s.x, s.y, 'edge', u)) list.push({ x: s.x, y: s.y, kind: 'edge' });
      }
      crowd.spots = list; crowd.spotsKey = key;
      return list;
    }

    // Two people overlap on screen when they are close sideways and less than a body height apart up and down
    // (someone just below stands in front of the other's body).
    const overlaps = (u, ax, ay, bx, by, gap = 16) => Math.abs(ax - bx) < gap * u && Math.abs(ay - by) < 38 * u;
    const clearOf = (u, p, x, y, gap) => crowd.people.every(o => o === p || o === p.partner || o.leaving ||
      (!overlaps(u, o.tx, o.ty, x, y, gap) && !overlaps(u, o.x, o.y, x, y, gap)));

    // a free spot of this kind, not in front of or behind anyone else, preferring nearer ones
    function findSpot(L, p, kind, gap) {
      const u = unitOf(L);
      const free = spots(L).filter(s => s.kind === kind && clearOf(u, p, s.x, s.y, gap * 0.75));
      if (!free.length) return null;
      let best = null, bd = Infinity;
      for (let i = 0; i < 5; i++) { const s = pick(free), d = Math.hypot(s.x - p.x, s.y - p.y); if (d < bd) { bd = d; best = s; } }
      return best;
    }

    const onScreen = (L, x, y, m = 0) => x > S.inset.left + m && x < S.W - S.inset.right - m && y > S.inset.top + m && y < S.H - S.inset.bottom - m;
    // A straight walk unless it would cross the record; then around it, along whichever side stays on screen
    // (the front of the record often runs into the bottom of the screen). Waypoints never leave the screen.
    function route(L, ax, ay, bx, by) {
      let hit = false;
      for (let t = 0.05; t < 1; t += 0.05) { const q = toPlane(L, lerp(ax, bx, t), lerp(ay, by, t)); if (Math.hypot(q.x, q.y) < 1.14) { hit = true; break; } }
      if (!hit) return [{ x: bx, y: by }];
      const A = toPlane(L, ax, ay), B = toPlane(L, bx, by), u = unitOf(L);
      const a0 = Math.atan2(A.y, A.x); let d = Math.atan2(B.y, B.x) - a0;
      while (d > Math.PI) d -= TAU; while (d < -Math.PI) d += TAU;
      const way = dd => {
        const n = Math.max(2, Math.ceil(Math.abs(dd) / 0.4)), pts = [];
        for (let i = 1; i < n; i++) { const a = a0 + dd * i / n; pts.push(toScreen(L, Math.cos(a) * 1.42 * L.R, Math.sin(a) * 1.42 * L.R)); }
        return pts;
      };
      const ways = [way(d), way(d > 0 ? d - TAU : d + TAU)];
      const off = pts => pts.filter(q => !onScreen(L, q.x, q.y, 6 * u)).length;
      const best = off(ways[0]) <= off(ways[1]) ? ways[0] : ways[1];
      const m = 8 * u, pts = best.map(q => ({ x: clamp(q.x, S.inset.left + m, S.W - S.inset.right - m), y: clamp(q.y, S.inset.top + 36 * u, S.H - S.inset.bottom - m) }));
      pts.push({ x: bx, y: by });
      return pts;
    }

    // ---------- the record as a running track ----------
    const RUN_R = 0.84;
    function recordPoint(L, a, r) {
      const p = toScreen(L, Math.cos(a) * r * L.R, Math.sin(a) * r * L.R), o = S.recOff;
      return { x: p.x + o.x * L.R, y: p.y + o.y * L.R - o.lift * 0.04 * L.R };
    }
    const recordSteady = () => S.shown && !S.cue && !S.recOff.lift && S.spinVel > 0.6 * TAU * RPS;
    // how the record's surface moves on screen at angle a (per unit of turn)
    const surfaceDir = a => ({ x: -Math.sin(a) * Math.cos(TILT) - Math.cos(a) * SQUASH * Math.sin(TILT), y: -Math.sin(a) * Math.sin(TILT) + Math.cos(a) * SQUASH * Math.cos(TILT) });
    // A treadmill spot: on the back or front of the record, where the surface moves left-right on screen, so the
    // runner faces one clear way. They run against the turn and stay in the same place.
    function runAngle(L, p) {
      const u = unitOf(L);
      for (let i = 0; i < 20; i++) {
        const a = chance(0.6) ? rand(-2.3, -0.9) : rand(1.25, 1.95), d = surfaceDir(a), q = recordPoint(L, a, RUN_R);
        if (Math.abs(d.x) < 0.8 * Math.hypot(d.x, d.y)) continue;
        const near = recordPoint(L, a, 1.3);   // where they walk to before stepping on: on screen
        if (spotOK(L, q.x, q.y, 'run', u) && clearOf(u, p, q.x, q.y, 16) && onScreen(L, near.x, near.y, 8 * u) && near.y - 36 * u > S.inset.top) return a;
      }
      return null;
    }
    const runFace = a => (surfaceDir(a).x > 0 ? -1 : 1);
    // stepping between the record's edge area (1.3 radii) and the running track, at the usual walking speed
    const stepTime = (L, p, a) => { const A = recordPoint(L, a, 1.3), B = recordPoint(L, a, RUN_R); return Math.max(0.4, Math.hypot(A.x - B.x, A.y - B.y) / (30 * unitOf(L) * p.k * p.pace)); };

    // ---------- comings and goings ----------
    const FRONT_OK = ['idle', 'hello', 'bye', 'dance', 'headbang', 'phone'];
    // Each new action may turn the person: toward the record and the music, or any way at all, and sometimes they
    // face the viewer.
    function startAct(L, p, act, dur) {
      p.act = act; p.t = 0; p.dur = dur;
      p.style = Math.floor(Math.random() * 3);
      p.idle = pick(['stand', 'stand', 'stretch', 'look', 'tap', 'cup']);
      const sitting = p.kind === 'edge' || act === 'read' || act === 'doze' || act === 'swing';
      p.view = !sitting && FRONT_OK.includes(act) && chance(act === 'hello' || act === 'bye' ? 0.7 : 0.4) ? 'front' : 'side';
      if (!sitting && act !== 'play' && act !== 'wait' && !p.runs) p.face = chance(0.55) ? toward(L, p) : (chance(0.5) ? 1 : -1);
    }

    function goTo(L, p, x, y, then) {
      p.tx = x; p.ty = y; p.path = route(L, p.x, p.y, x, y); p.then = then; p.act = 'walk'; p.t = 0; p.view = 'side';
    }

    function spawn(L, C) {
      const u = unitOf(L), small = chance(0.2), p = {
        look: makeLook(C), k: small ? rand(0.78, 0.86) : rand(0.92, 1.08), pace: rand(0.85, 1.2),
        x: 0, y: 0, tx: 0, ty: 0, face: 1, path: [], act: 'walk', t: 0, dur: 0, view: 'side',
        kind: 'stand', seed: rand(0, 100), walkPhase: 0, blinkAt: 0, partner: null, then: null, leaving: false,
      };
      const s = findSpot(L, p, 'stand', 22) || findSpot(L, p, 'edge', 22);
      if (!s) return;
      const fromLeft = s.x < S.W / 2;
      p.x = fromLeft ? S.inset.left - 24 * u : S.W - S.inset.right + 24 * u;
      p.y = clamp(s.y + rand(-30, 30), S.inset.top + 40 * u, S.H - S.inset.bottom - 10);
      p.face = fromLeft ? 1 : -1;
      crowd.people.push(p);
      goTo(L, p, s.x, s.y, () => { p.kind = s.kind; startAct(L, p, 'hello', 1.3); });
    }

    function endPlay(L, q) { if (!q) return; q.partner = null; if (!q.leaving) startAct(L, q, 'idle', rand(1, 3)); }

    function sendHome(L, p) {
      p.leaving = true;
      if (p.partner) { const q = p.partner; p.partner = null; if (q.partner === p) endPlay(L, q); }
      if (p.runs) { p.after = null; startAct(L, p, 'tumble', 1); return; }
      startAct(L, p, 'bye', 1.4);
      p.after = () => {
        const u = unitOf(L), left = p.x < S.W / 2;
        goTo(L, p, left ? S.inset.left - 30 * u : S.W - S.inset.right + 30 * u, p.y, () => { p.gone = true; });
      };
    }

    // what to do next, weighted by whether the music is playing
    function nextAct(L, p, forced) {
      const playing = S.media.state === 'playing', u = unitOf(L);
      const hasEdge = spots(L).some(s => s.kind === 'edge');
      const mates = crowd.people.filter(o => o !== p && !o.leaving && !o.partner && (o.act === 'idle' || o.act === 'dance' || o.act === 'phone'));
      const runners = crowd.people.filter(o => o.runs).length;
      const W8 = playing
        ? { dance: 3, headbang: 1.2, bboy: 0.9, swing: hasEdge ? 1.5 : 0, read: 0.8, doze: 0.5, phone: 0.8, walk: 1.4, idle: 1, play: mates.length ? 1.6 : 0, run: recordSteady() && runners < 2 ? 0.9 : 0 }
        : { swing: hasEdge ? 1.4 : 0, read: 2, doze: 2, phone: 1.6, walk: 1, idle: 1.4, play: mates.length ? 0.8 : 0 };
      let sum = 0; for (const k in W8) sum += W8[k];
      let r = Math.random() * sum, act = 'idle';
      for (const k in W8) { r -= W8[k]; if (r <= 0) { act = k; break; } }
      if (forced) act = forced;
      const dur = { dance: rand(18, 36), headbang: rand(9, 16), bboy: 18, swing: rand(25, 50), read: rand(30, 60), doze: rand(25, 50), phone: rand(16, 30), idle: rand(5, 12) }[act];

      if (act === 'walk') {
        const s = findSpot(L, p, chance(0.2) && hasEdge ? 'edge' : 'stand', 22);
        if (s) goTo(L, p, s.x, s.y, () => { p.kind = s.kind; startAct(L, p, 'idle', rand(2, 5)); });
        else startAct(L, p, 'idle', 3);
        return;
      }
      if (act === 'run') {
        const a = runAngle(L, p);
        if (a === null) { startAct(L, p, 'idle', 3); return; }
        const near = toScreen(L, Math.cos(a) * 1.3 * L.R, Math.sin(a) * 1.3 * L.R);
        goTo(L, p, near.x, near.y, () => { p.kind = 'stand'; p.ra = a; p.from = { x: p.x, y: p.y }; p.runs = true; startAct(L, p, 'stepon', stepTime(L, p, a)); });
        return;
      }
      if (act === 'play') {
        const q = pick(mates), side = chance(0.5) ? 1 : -1, gap = 13 * u;
        // the partner's spot is beside this one; if it doesn't fit, try the other side
        let bx = p.x + side * gap, ok = spotOK(L, bx, p.y, 'stand', u);
        if (!ok) { bx = p.x - side * gap; ok = spotOK(L, bx, p.y, 'stand', u); }
        if (p.kind !== 'stand' || !ok) { startAct(L, p, 'idle', 2); return; }
        const game = pick(['highfive', 'twirl', 'tag']), d = rand(9, 14);
        p.partner = q; q.partner = p; p.game = q.game = game;
        startAct(L, p, 'wait', 30); p.face = bx > p.x ? 1 : -1;
        goTo(L, q, bx, p.y, () => {
          q.kind = 'stand'; startAct(L, q, 'play', d); startAct(L, p, 'play', d);
          q.face = p.x > q.x ? 1 : -1; p.face = -q.face; p.view = q.view = 'side';
          p.home = { x: p.x, y: p.y }; q.home = { x: q.x, y: q.y };
        });
        return;
      }
      const need = act === 'swing' ? 'edge' : act === 'read' || act === 'doze' ? null : 'stand';
      if (need && p.kind !== need) {
        const s = findSpot(L, p, need, act === 'bboy' ? 34 : 22);
        if (!s) { startAct(L, p, 'idle', 3); return; }
        goTo(L, p, s.x, s.y, () => { p.kind = s.kind; startAct(L, p, act, dur); });
        return;
      }
      if (act === 'bboy' && crowd.people.some(o => o !== p && Math.hypot(o.x - p.x, o.y - p.y) < 30 * u)) {
        const s = findSpot(L, p, 'stand', 34);
        if (s) { goTo(L, p, s.x, s.y, () => { p.kind = 'stand'; startAct(L, p, 'bboy', dur); }); return; }
        startAct(L, p, 'dance', dur); return;
      }
      startAct(L, p, act, dur);
    }

    // ---------- every frame ----------
    function update(dt, now) {
      const L = layout(), u = unitOf(L), people = crowd.people, media = S.media, opts = S.opts;
      const playing = media.state === 'playing', k = speed();
      // test copies only: the state, and a way to send someone to a given action through the normal path
      if (S.NATIVE && S.NATIVE.crowdSpeed) { window.__crowd = crowd; window.__crowdDo = (p, act) => nextAct(layout(), p, act); }
      if (playing) crowd.beat += dt * (media.bpm || 100) / 60;
      if (!opts.crowd || opts.transparent) {
        for (const p of people) if (!p.leaving) sendHome(L, p);
      } else if (playing) {
        // back from a break: those still here stay, and the next arrival comes after the usual wait
        if (crowd.stopped) {
          crowd.stopped = false; crowd.play = 0;
          crowd.nextAt = people.some(p => !p.leaving) ? rand(180, 300) : rand(180, 420);
        }
        crowd.idle = 0; crowd.leaveAt = rand(30, 60); crowd.play += dt * k;
        if (crowd.play >= crowd.nextAt && people.filter(p => !p.leaving).length < MAX) {
          spawn(L, S.sceneColors()); crowd.nextAt = crowd.play + rand(180, 300);
        }
      } else {
        // no music: one person goes home every 30-60 seconds
        crowd.idle += dt * k; crowd.stopped = true;
        const stay = people.filter(p => !p.leaving);
        if (stay.length && crowd.idle >= crowd.leaveAt) { sendHome(L, pick(stay)); crowd.leaveAt = crowd.idle + rand(30, 60); }
      }
      // a new song: whoever is standing around cheers
      const tk = media.title + '|' + media.artist;
      if (tk !== crowd.trackKey) {
        if (crowd.trackKey && playing) for (const p of people) if (['idle', 'dance', 'headbang', 'phone'].includes(p.act) && p.kind === 'stand') p.cheer = 1.5;
        crowd.trackKey = tk;
      }

      // anyone standing in front of or behind someone else moves over (checked now and then, one person at a time)
      if ((crowd.sepT = (crowd.sepT || 0) + dt) > 1.2) {
        crowd.sepT = 0;
        const still = people.filter(p => !p.leaving && !p.runs && !p.partner && !['walk', 'play', 'wait', 'hello', 'bye'].includes(p.act));
        for (const p of still) {
          if (!still.some(o => o !== p && overlaps(u, o.x, o.y, p.x, p.y, 13))) continue;
          const s = findSpot(L, p, p.kind === 'edge' ? 'edge' : 'stand', 22);
          if (s) goTo(L, p, s.x, s.y, () => { p.kind = s.kind; startAct(L, p, 'idle', rand(1, 3)); });
          break;
        }
      }
      for (const p of people) {
        p.t += dt;
        if (p.blinkAt < now) { p.blinkUntil = now + 130; p.blinkAt = now + rand(2200, 5200); }
        if (p.cheer > 0) p.cheer = Math.max(0, p.cheer - dt);
        if (p.act === 'walk') {
          const tgt = p.path[0];
          if (!tgt) { const f = p.then; p.then = null; p.act = 'idle'; p.t = 0; p.dur = 2; if (f) f(); continue; }
          const dx = tgt.x - p.x, dy = tgt.y - p.y, d = Math.hypot(dx, dy), v = 30 * u * p.k * p.pace * (p.leaving ? 1.25 : 1);
          if (d < v * dt) { p.x = tgt.x; p.y = tgt.y; p.path.shift(); }
          else { p.x += dx / d * v * dt; p.y += dy / d * v * dt; if (Math.abs(dx) > 0.5) p.face = dx > 0 ? 1 : -1; }
          p.walkPhase += dt * v / (5.5 * u);
          continue;
        }
        if (p.kind === 'edge' && !p.leaving) p.face = -1;   // edge-sitters look out over the side

        // on the record: walk on, run against the turn like on a treadmill, walk off (or get flung off by a record swap)
        if (p.runs) { updateRunner(L, p, dt, u); continue; }

        if (p.act === 'wait') { if (!p.partner) startAct(L, p, 'idle', 1); continue; }
        if (p.act === 'play' && p.game === 'tag' && p.home) {
          // tag: the two take turns chasing each other around a little circle
          const a = p.t * 1.6 + (p.face > 0 ? 0 : Math.PI), r = 7 * u;
          const nx = p.home.x + Math.cos(a) * r * (p.face > 0 ? 1 : -1), ny = p.home.y + Math.sin(a) * r * 0.45;
          if (Math.abs(nx - p.x) > 0.2) p.chaseFace = nx > p.x ? 1 : -1;
          p.x = nx; p.y = ny; p.walkPhase += dt * 9;
        }
        // the music stopped: dancers stop; the music came back: dozers wake with a start
        if (!playing && ['dance', 'headbang', 'bboy'].includes(p.act)) p.t = p.dur;
        if (playing && p.act === 'doze' && p.wasPlaying === false) {
          crowd.fx.push({ type: 'bang', x: p.x + p.face * 4 * u * p.k, y: p.y - 32 * u * p.k, t: 0, life: 0.9 }); p.t = p.dur;
        }
        p.wasPlaying = playing;
        if (p.t >= p.dur) {
          if (p.act === 'bye') { const f = p.after; p.after = null; if (f) f(); continue; }
          if (p.leaving) continue;
          if (p.act === 'play') {
            const q = p.partner; p.partner = null; if (p.home) { p.x = p.home.x; p.y = p.home.y; p.home = null; }
            if (q && q.partner === p) { q.partner = null; if (q.home) { q.x = q.home.x; q.y = q.home.y; q.home = null; } startAct(L, q, 'idle', rand(1, 3)); }
          }
          nextAct(L, p);
        }
      }
      crowd.people = people.filter(p => !p.gone);
      for (const f of crowd.fx) f.t += dt;
      crowd.fx = crowd.fx.filter(f => f.t < f.life);
    }

    function updateRunner(L, p, dt, u) {
      // walking onto the record from just outside it; the record already carries them a little
      if (p.act === 'stepon') {
        const e = clamp(p.t / p.dur), q = recordPoint(L, p.ra, lerp(1.3, RUN_R, e));
        if (Math.abs(q.x - p.x) > 0.3) p.face = q.x > p.x ? 1 : -1;
        p.walkPhase += dt * 30 * p.k * p.pace / 5.5; p.x = q.x; p.y = q.y;
        if (e >= 1) { startAct(L, p, 'run', rand(8, 16)); p.face = runFace(p.ra); }
        return;
      }
      if (p.act === 'run') {
        // like a treadmill: they stay in place and the legs keep pace with the record's surface under them
        const surface = S.spinVel * RUN_R * L.R * Math.hypot(surfaceDir(p.ra).x, surfaceDir(p.ra).y);   // px/s on screen
        p.walkPhase += dt * Math.min(28, surface / (5.5 * u));
        const q = recordPoint(L, p.ra, RUN_R); p.x = q.x; p.y = q.y; p.face = runFace(p.ra);
        if (chance(dt * 0.25)) crowd.fx.push({ type: 'drop', x: p.x - p.face * 5 * u * p.k, y: p.y - 30 * u * p.k, t: 0, life: 0.8 });
        // the record is lifted off for a swap: flung off. It slowed down or the time is up: walk off.
        if (S.cue && S.recOff.lift) { startAct(L, p, 'tumble', 1); p.from = { x: p.x, y: p.y }; }
        else if (S.spinVel < 0.35 * TAU * RPS || p.t >= p.dur) { startAct(L, p, 'stepoff', stepTime(L, p, p.ra)); p.from = { x: p.x, y: p.y }; }
        return;
      }
      if (p.act === 'stepoff') {
        const e = clamp(p.t / p.dur), q = recordPoint(L, p.ra, lerp(RUN_R, 1.32, e));
        if (Math.abs(q.x - p.x) > 0.3) p.face = q.x > p.x ? 1 : -1;
        p.walkPhase += dt * 30 * p.k * p.pace / 5.5; p.x = q.x; p.y = q.y;
        if (e >= 1) { p.runs = false; p.kind = 'stand'; if (p.leaving) { startAct(L, p, 'bye', 0.6); p.after = goHome(L, p); } else startAct(L, p, 'idle', rand(1, 2)); }
        return;
      }
      if (p.act === 'tumble') {
        // flung off: carried along with the turn while sliding outward, rolling over, then a dizzy sit
        const e = clamp(p.t / p.dur);
        p.ra += S.spinVel * dt; const q = recordPoint(L, p.ra, lerp(RUN_R, 1.32, easeOut(e)));
        p.x = q.x; p.y = q.y; p.roll = e * TAU * 1.5 * -p.face; p.hopArc = Math.sin(e * Math.PI) * 6 * u;
        if (e >= 1) { p.roll = 0; p.hopArc = 0; p.runs = false; p.kind = 'stand'; startAct(L, p, 'dazed', 2.6); }
        return;
      }
    }
    const goHome = (L, p) => () => {
      const u = unitOf(L), left = p.x < S.W / 2;
      goTo(L, p, left ? S.inset.left - 30 * u : S.W - S.inset.right + 30 * u, p.y, () => { p.gone = true; });
    };

    // ---------- poses ----------
    // Side view: the canonical figure faces +x, origin at the hip, y down. Distances are in u (scales with the record).
    function sidePose(p, act, now, u) {
      const t = p.t, beat = crowd.beat + p.seed * 0.137, bp = beat % 1, pulse = Math.pow(1 - bp, 3);
      const P = { hipY: -9 * u, lean: 0, head: 0, armB: [-1.8 * u, -1.4 * u], armF: [2.2 * u, -1.2 * u], legB: null, legF: null, sit: '', mouth: '', eyes: 'open', prop: '' };
      const legs = (sb, sf, lift) => {
        P.legB = { kx: -0.6 * u + sb * 0.5, ky: 4.4 * u - (lift || 0), fx: -0.8 * u + sb, fy: 9 * u };
        P.legF = { kx: 0.8 * u + sf * 0.5, ky: 4.4 * u - (lift || 0), fx: 1 * u + sf, fy: 9 * u };
      };
      const stride = (ph, len) => {
        const s = Math.sin(ph); legs(-s * len, s * len, 0.6 * u);
        P.legB.fy -= Math.max(0, s) * 1.4 * u; P.legF.fy -= Math.max(0, -s) * 1.4 * u;
        P.hipY -= Math.abs(Math.cos(ph)) * 0.8 * u;
        return s;
      };
      legs(0, 0);
      switch (act) {
        case 'walk': {
          const s = stride(p.walkPhase, 2.6 * u);
          P.armB = [-1.6 * u + s * 2.4 * u, -1.6 * u]; P.armF = [2 * u - s * 2.4 * u, -1.4 * u]; P.lean = 0.06;
          break;
        }
        case 'run': {
          // a real running stride: thigh swings, the knee comes up in front and the heel kicks up behind,
          // the body bobs twice per stride and the bent arms pump against the legs
          const ph = p.walkPhase, runLeg = q => {
            const th = 0.95 * Math.sin(q), sh = th - 0.25 - 1.25 * Math.max(0, -Math.cos(q));
            const kx = Math.sin(th) * 4.6 * u, ky = Math.cos(th) * 4.6 * u;
            return { kx, ky, fx: kx + Math.sin(sh) * 4.6 * u, fy: ky + Math.cos(sh) * 4.6 * u };
          };
          P.legF = runLeg(ph); P.legB = runLeg(ph + Math.PI);
          P.hipY = -8.6 * u - Math.abs(Math.sin(ph)) * 1.4 * u;
          P.lean = 0.26;
          const s = Math.sin(ph);
          P.armF = [3.2 * u - s * 3.4 * u, -7.4 * u - s * 1.6 * u]; P.armB = [3.2 * u + s * 3.4 * u, -7.4 * u + s * 1.6 * u];
          P.mouth = 'smile';
          break;
        }
        case 'stepon': case 'stepoff': {
          const s = stride(p.walkPhase, 2.6 * u);
          P.armB = [-1.6 * u + s * 2.4 * u, -1.6 * u]; P.armF = [2 * u - s * 2.4 * u, -1.4 * u]; P.lean = 0.06; P.mouth = 'smile';
          break;
        }
        case 'tumble': P.mouth = 'o'; P.eyes = 'closed'; P.armB = [-5 * u, -12 * u]; P.armF = [5 * u, -14 * u]; legs(-2 * u, 2 * u, 3 * u); break;
        case 'hello': case 'bye': P.armF = [3 * u + Math.sin(t * 14) * 1.6 * u, -27 * u]; P.mouth = 'smile'; break;
        case 'wait': case 'idle': idlePose(p, P, now, u, pulse, 'side'); break;
        case 'dance': {
          const sway = Math.sin(beat * Math.PI), bob = pulse * 1.6 * u;
          P.hipY += bob * 0.6; P.mouth = 'smile';
          if (p.style === 0) {   // arms up, swaying
            const up = Math.floor(beat) % 2;
            P.armB = up ? [-3 * u, -24 * u] : [-4 * u, -8 * u]; P.armF = up ? [4 * u, -8 * u] : [3 * u, -25 * u];
            P.lean = sway * 0.12; legs(-sway * 1.2 * u, -sway * 1.2 * u, bob * 0.5);
          } else if (p.style === 1) {   // side steps: arms wide, then a clap
            const st = Math.sin(beat * Math.PI * 0.5), clap = bp < 0.18;
            legs(st * 2.2 * u - 1.2 * u, st * 2.2 * u + 1.2 * u, bob * 0.6);
            P.armB = clap ? [3 * u, -9 * u] : [-6 * u, -14 * u]; P.armF = clap ? [3.6 * u, -9.4 * u] : [7 * u, -15 * u];
            P.head = st * 0.1;
          } else {   // the twist
            const tw = Math.sin(beat * Math.PI);
            P.lean = tw * 0.16; P.hipY += 1.2 * u; legs(tw * 1.6 * u, -tw * 1.6 * u, 1.2 * u);
            P.armB = [-4 * u - tw * 2 * u, -6 * u]; P.armF = [4 * u - tw * 2 * u, -7 * u];
          }
          if (chance(0.004)) crowd.fx.push({ type: 'note', x: p.x + rand(-6, 6) * u, y: p.y - 38 * u * p.k, t: 0, life: 1.6, c: p.look.shirt });
          break;
        }
        case 'headbang': {
          P.lean = 0.12 + pulse * 0.32; P.head = 0.15 + pulse * 0.5; P.mouth = 'o';
          P.armB = [-2 * u, -2 * u];
          P.armF = Math.floor(beat / 4) % 2 ? [3 * u, -26 * u] : [5 * u, -6 * u];   // horns up every other bar
          legs(-1.4 * u, 1.6 * u, pulse * u); P.hair = pulse;
          break;
        }
        case 'bboy': {
          const c = t % 9, last = p.lastB; p.lastB = c;
          if (c < 2.5) {   // toprock
            const s = Math.sin(c * Math.PI * 1.6);
            legs(s * 2.4 * u, -s * 1.4 * u, Math.max(0, s) * 1.6 * u);
            P.armB = [2 * u + s * 2 * u, -9 * u]; P.armF = [4 * u - s * 2 * u, -10 * u]; P.lean = 0.08; P.mouth = 'smile';
          } else if (c < 3) {   // drop
            const e = (c - 2.5) / 0.5; P.hipY = lerp(-9 * u, -3 * u, e);
            legs(-2 * u, 3 * u, e * 3 * u); P.armF = [5 * u, -2 * u];
          } else if (c < 5.5) {   // headspin: upside down, spinning
            P.flip = true; P.hipY = 0; P.sx = Math.cos((c - 3) * TAU * 2.2); P.mouth = 'o';
            P.legB = { kx: -2.2 * u, ky: 4 * u, fx: -4.8 * u, fy: 8 * u }; P.legF = { kx: 2.2 * u, ky: 4 * u, fx: 4.8 * u, fy: 8 * u };
            P.armB = [-5 * u, -16 * u]; P.armF = [5 * u, -16 * u];
          } else if (c < 6.7) {   // freeze
            P.freeze = true; P.hipY = 0; P.mouth = 'smile';
            P.legB = { kx: 2 * u, ky: 3 * u, fx: 0, fy: 6 * u }; P.legF = { kx: 3.5 * u, ky: 1 * u, fx: 7 * u, fy: 1 * u };
            P.armB = [-1 * u, -4 * u]; P.armF = [0, -20 * u];
            if (last < 5.5) crowd.fx.push({ type: 'spark', x: p.x, y: p.y - 22 * u * p.k, t: 0, life: 0.6 });
          } else if (c < 7.2) {   // up
            const e = (c - 6.7) / 0.5; P.hipY = lerp(-3 * u, -9 * u, e); legs(0, 0, (1 - e) * 3 * u);
          } else {   // pose, arms crossed
            P.armB = [3 * u, -9 * u]; P.armF = [3.5 * u, -9.6 * u]; P.lean = -0.08; P.mouth = 'smile'; P.hipY += pulse * 0.8 * u;
          }
          break;
        }
        case 'phone': {
          P.armF = [3.4 * u, -18.5 * u]; P.prop = 'phone';
          const g = Math.sin(now / 420 + p.seed);
          P.armB = [-1 * u + g * 2 * u, -6 * u - Math.abs(g) * 3 * u];
          // pacing a little while talking
          if (Math.sin(now / 3000 + p.seed) > 0.6) { stride(now / 180, 1.6 * u); }
          phoneTalk(p, P, now, u);
          break;
        }
        case 'swing': case 'read': case 'doze': case 'dazed': seated(p, P, act, now, u, t, pulse); break;
        case 'play': {
          const q = p.partner;
          if (p.game === 'highfive') {
            const c = (t + 0.2) % 1.8, j = c > 0.5 && c < 1.1 ? Math.sin((c - 0.5) / 0.6 * Math.PI) : 0;
            P.hipY -= j * 6 * u; P.mouth = 'smile';
            P.armF = c > 0.4 && c < 1.15 ? [5.6 * u, -24 * u] : [3 * u, -4 * u];
            if (j > 0) legs(-u, u, j * 2 * u);
            const crossed = p.lastC !== undefined && p.lastC < 0.79 && c >= 0.79; p.lastC = c;
            if (q && p.face > 0 && crossed) {
              crowd.fx.push({ type: 'spark', x: (p.x + q.x) / 2, y: p.y - 33 * u * p.k, t: 0, life: 0.5 });
              if (chance(0.6)) crowd.fx.push({ type: 'heart', x: (p.x + q.x) / 2, y: p.y - 40 * u * p.k, t: 0, life: 1.3 });
            }
          } else if (p.game === 'twirl') {
            // holding hands and hopping in turn, swaying together
            const ph = t * Math.PI * 2 * 0.9 + (p.face > 0 ? 0 : Math.PI), hop = Math.max(0, Math.sin(ph));
            P.hipY -= hop * 3 * u; P.lean = Math.sin(t * 2.4) * 0.1 * p.face; P.mouth = 'smile';
            P.armF = [6.4 * u, -9 * u]; P.armB = [-3 * u, -5 * u];
            if (hop > 0) legs(-u, u, hop * 1.5 * u);
            if (p.face > 0 && chance(0.012)) crowd.fx.push({ type: 'heart', x: q ? (p.x + q.x) / 2 : p.x, y: p.y - 36 * u * p.k, t: 0, life: 1.4 });
          } else {
            // tag: running in a little circle, laughing
            const s = stride(p.walkPhase, 3 * u);
            P.lean = 0.14; P.mouth = 'o'; P.armB = [-3 * u + s * 3 * u, -7 * u]; P.armF = [3 * u - s * 3 * u, -8 * u];
            if (p.face > 0 && chance(0.008)) crowd.fx.push({ type: 'heart', x: p.x, y: p.y - 38 * u * p.k, t: 0, life: 1.2 });
          }
          break;
        }
      }
      if (p.cheer > 0 && !P.sit) cheer(p, P, u, 'side');
      if (now < p.blinkUntil && P.eyes === 'open') P.eyes = 'blink';
      return P;
    }

    function idlePose(p, P, now, u, pulse, view) {
      const t = p.t;
      P.hipY += Math.sin(now / 900 + p.seed) * 0.25 * u;
      P.head = Math.sin(now / 2300 + p.seed) * 0.08;
      if (S.media.state === 'playing') P.head += pulse * 0.08;
      const front = view === 'front';
      if (p.idle === 'stretch' && t < 2.2) {
        const e = Math.sin(clamp(t / 2.2) * Math.PI);
        if (front) { P.armL = [-3 * u, lerp(-2, -26, e) * u]; P.armR = [3 * u, lerp(-2, -26, e) * u]; }
        else { P.armB = [0, lerp(-2, -26, e) * u]; P.armF = [1 * u, lerp(-2, -26, e) * u]; }
        P.eyes = e > 0.5 ? 'closed' : 'open'; P.mouth = e > 0.5 ? 'o' : '';
      } else if (p.idle === 'look') {
        // looking over at the record now and then (turning around in side view)
        if (!front && Math.floor((t + p.seed) / 3) % 2) p.lookBack = true; else p.lookBack = false;
        P.head += Math.sin(t * 1.3) * 0.12;
      } else if (p.idle === 'tap' && S.media.state === 'playing') {
        if (front) P.tapR = pulse * 1.4 * u; else { P.legF.fy -= pulse * 1.4 * u; P.legF.fx += pulse * 0.8 * u; }
      } else if (p.idle === 'cup') {
        const sip = (t % 5) < 1.2;
        P.prop = 'cup';
        if (front) P.armR = sip ? [1 * u, -15.5 * u] : [4.4 * u, -6 * u];
        else P.armF = sip ? [3.6 * u, -15.5 * u] : [4.2 * u, -6.4 * u];
        if (sip) P.eyes = 'closed';
      }
    }

    function phoneTalk(p, P, now, u) {
      const laugh = Math.sin(now / 2600 + p.seed * 3) > 0.92;
      if (laugh) { P.head = -0.25 + Math.sin(now / 70) * 0.05; P.mouth = 'o'; P.hipY -= Math.abs(Math.sin(now / 90)) * 0.8 * u; }
      else P.mouth = Math.sin(now / 160 + p.seed) > 0.2 ? 'o' : '';
      if (chance(0.006)) crowd.fx.push({ type: laugh ? 'heart' : 'dots', x: p.x + p.face * 9 * u * p.k, y: p.y - 40 * u * p.k, t: 0, life: 1.4 });
    }

    function cheer(p, P, u, view) {
      const e = 1 - p.cheer / 1.5, j = Math.abs(Math.sin(e * Math.PI * 2));
      P.hipY -= j * 4 * u; P.mouth = 'o';
      if (view === 'front') { P.armL = [-4.5 * u, -26 * u]; P.armR = [4.5 * u, -26 * u]; }
      else { P.armB = [-1 * u, -26 * u]; P.armF = [3 * u, -26 * u]; }
    }

    // Sitting: on the plinth's edge with the legs over the side, or on the floor with the knees up. No bouncing here.
    function seated(p, P, act, now, u, t, pulse) {
      const edge = p.kind === 'edge';
      if (edge) {
        P.sit = 'edge'; P.hipY = 0;
        const w = 0.6 + 0.4 * wander(now / 1000 * 0.4 + p.seed);
        const sw1 = act === 'swing' ? w * Math.sin(now / 1000 * 3.2 + p.seed) : 0.15 * Math.sin(now / 1400);
        const sw2 = act === 'swing' ? w * Math.sin(now / 1000 * 3.2 + p.seed + Math.PI + 0.6 * wander(now / 3000 + p.seed)) : -0.15 * Math.sin(now / 1400);
        P.legB = { kx: 3 * u, ky: 0.4 * u, fx: 3 * u + sw2 * 2.4 * u, fy: 8.4 * u - Math.abs(sw2) * 0.8 * u };
        P.legF = { kx: 4.6 * u, ky: 0.4 * u, fx: 4.6 * u + sw1 * 2.4 * u, fy: 8.4 * u - Math.abs(sw1) * 0.8 * u };
        P.armB = [-3.4 * u, -0.6 * u]; P.armF = [3 * u, -0.4 * u];
      } else {
        P.sit = 'floor'; P.hipY = -2.6 * u;
        P.legB = { kx: 3.4 * u, ky: -3.4 * u, fx: 6 * u, fy: 2.6 * u }; P.legF = { kx: 4 * u, ky: -3.2 * u, fx: 6.6 * u, fy: 2.6 * u };
        P.armB = [-4 * u, 1.8 * u]; P.armF = [4.4 * u, -3.6 * u];
      }
      if (act === 'swing') {
        if (S.media.state === 'playing') P.head = pulse * 0.1;
        P.mouth = 'smile';
      } else if (act === 'read') {
        P.armB = [4.6 * u, -6 * u]; P.armF = [5.4 * u, -6.4 * u]; P.prop = 'book';
        P.head = 0.28 + Math.sin(now / 1800 + p.seed) * 0.04; P.lean = 0.06;
        P.page = (t % 6) < 0.5 ? (t % 6) / 0.5 : -1;
      } else if (act === 'dazed') {
        P.head = Math.sin(now / 160) * 0.2; P.eyes = 'swirl'; P.mouth = 'o'; P.dizzy = true;
      } else {
        // nodding off: the head sinks slowly, then jerks back up
        const cyc = 4.2 + (p.seed % 1.5), c = (t + p.seed) % cyc, sink = c < cyc - 0.35 ? easeInOut(c / (cyc - 0.35)) : 1 - (c - (cyc - 0.35)) / 0.35;
        P.head = 0.1 + sink * 0.55; P.lean = 0.04 + sink * 0.14; P.eyes = sink > 0.25 ? 'closed' : 'open';
        if (!edge) { P.armB = [3 * u, -2.4 * u]; P.armF = [4 * u, -2.6 * u]; }
        if (chance(0.01) && sink > 0.5) crowd.fx.push({ type: 'z', x: p.x + p.face * 5 * u * p.k, y: p.y - (edge ? 30 : 26) * u * p.k, t: 0, life: 2.2 });
      }
    }

    // Front view: facing the viewer, origin at the hip. armL/armR are hand positions; shoulders at (±4, -11.4).
    function frontPose(p, act, now, u) {
      const t = p.t, beat = crowd.beat + p.seed * 0.137, bp = beat % 1, pulse = Math.pow(1 - bp, 3);
      const P = { hipY: -9 * u, dx: 0, armL: [-5.2 * u, -1.5 * u], armR: [5.2 * u, -1.5 * u], head: 0, headY: 0, mouth: '', eyes: 'open', prop: '', liftL: 0, liftR: 0, tapR: 0 };
      P.dx = Math.sin(now / 1500 + p.seed) * 0.3 * u;
      switch (act) {
        case 'hello': case 'bye': P.armR = [6 * u + Math.sin(t * 14) * 1.6 * u, -25 * u]; P.mouth = 'smile'; break;
        case 'idle': idlePose(p, P, now, u, pulse, 'front'); break;
        case 'dance': {
          P.mouth = 'smile';
          if (p.style === 0) {   // one arm up, then the other
            const up = Math.floor(beat) % 2;
            P.armL = up ? [-4 * u, -25 * u] : [-6.4 * u, -6 * u]; P.armR = up ? [6.4 * u, -6 * u] : [4 * u, -25 * u];
            P.dx = Math.sin(beat * Math.PI) * 1.4 * u; P.hipY += pulse * u; P.liftL = up ? 0 : pulse * 1.2 * u; P.liftR = up ? pulse * 1.2 * u : 0;
          } else if (p.style === 1) {   // robot
            const b = Math.floor(beat) % 4;
            P.armL = [[-8 * u, -11 * u], [-5 * u, -20 * u], [-8 * u, -11 * u], [-4 * u, -4 * u]][b];
            P.armR = [[5 * u, -20 * u], [8 * u, -11 * u], [4 * u, -4 * u], [8 * u, -11 * u]][b];
            P.head = [0.12, -0.12, 0.12, -0.12][b]; P.mouth = '';
          } else {   // jumping, arms up in the air
            const j = Math.max(0, Math.sin(beat * Math.PI));
            P.hipY -= j * 4 * u; P.liftL = P.liftR = j * 2 * u;
            P.armL = [-4.5 * u, -25 * u + (1 - j) * 6 * u]; P.armR = [4.5 * u, -25 * u + (1 - j) * 6 * u];
          }
          if (chance(0.004)) crowd.fx.push({ type: 'note', x: p.x + rand(-6, 6) * u, y: p.y - 38 * u * p.k, t: 0, life: 1.6, c: p.look.shirt });
          break;
        }
        case 'headbang': {
          P.headY = pulse * 2.6 * u; P.head = Math.sin(beat * Math.PI) * 0.1; P.mouth = 'o'; P.hair = pulse;
          const horns = Math.floor(beat / 4) % 2;
          P.armL = horns ? [-5 * u, -24 * u] : [-5.6 * u, -3 * u]; P.armR = horns ? [5 * u, -24 * u] : [5.6 * u, -3 * u];
          P.hipY += pulse * 0.8 * u;
          break;
        }
        case 'phone': {
          P.armR = [5.4 * u, -17.4 * u]; P.prop = 'phone'; P.armL = [-6.4 * u, -5 * u];   // other hand on the hip
          phoneTalk(p, P, now, u);
          break;
        }
      }
      if (p.cheer > 0) cheer(p, P, u, 'front');
      if (now < p.blinkUntil && P.eyes === 'open') P.eyes = 'blink';
      return P;
    }

    // ---------- drawing ----------
    const limb = (x1, y1, mx, my, x2, y2, col, w) => {
      ctx.strokeStyle = col; ctx.lineWidth = w;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.quadraticCurveTo(mx, my, x2, y2); ctx.stroke();
    };

    function drawPerson(p, L, now) {
      const u = unitOf(L) * p.k; p.u = u;
      const lift = p.hopArc || 0;
      ctx.save(); ctx.translate(p.x, p.y);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      if (p.view === 'front' && !p.runs) drawFront(p, L, now, u, lift);
      else drawSide(p, L, now, u, lift);
      ctx.restore();
    }

    function shadow(x, y, w) { ctx.fillStyle = 'rgba(0,0,0,0.14)'; ctx.beginPath(); ctx.ellipse(x, y, w, w / 3, 0, 0, TAU); ctx.fill(); }

    function drawSide(p, L, now, u, up) {
      const act = p.kind === 'edge' && (p.act === 'idle' || p.act === 'wait') ? 'swing' : p.act;
      const P = sidePose(p, act, now, u), lk = p.look;
      let face = p.act === 'play' && p.game === 'tag' && p.chaseFace ? p.chaseFace : p.face;
      if (p.lookBack) face = -face;
      const shirt = hex(lk.shirt), shirtD = css(mix(shirt, [0, 0, 0], 0.2)), pants = hex(lk.pants), pantsD = css(mix(pants, [0, 0, 0], 0.28));
      const sit = P.sit === 'edge';
      shadow(sit ? face * 4 * u : 0, sit ? PLINTH_T * L.R + u : 0.6 * u, (P.flip || P.freeze ? 9 : 6) * u);
      ctx.translate(0, -up);
      if (p.roll) { ctx.translate(0, -12 * u); ctx.rotate(p.roll); ctx.translate(0, 12 * u); }
      // headspin: upside down with the top of the head on the floor (hip 22.5u up); freeze: tipped over onto one hand
      if (P.flip) { ctx.translate(0, -22.5 * u); ctx.rotate(Math.PI); ctx.scale(Math.sign(P.sx || 1) * Math.max(0.3, Math.abs(P.sx)), 1); }
      else if (P.freeze) { ctx.translate(0, -20 * u); ctx.rotate((Math.PI - 0.5) * face); }
      ctx.scale(face, 1);
      ctx.translate(0, P.hipY);
      const shoe = (fx, fy) => { ctx.fillStyle = lk.shoes; rrect(ctx, fx - 2 * u, fy - 2.6 * u, 5.2 * u, 2.8 * u, 1.2 * u); ctx.fill(); };
      const leg = (dx, l, col) => {
        limb(dx, 0, (dx + l.kx) / 2, l.ky / 2 + 0.3 * u, l.kx, l.ky, col, 3.6 * u);
        limb(l.kx, l.ky, (l.kx + l.fx) / 2, (l.ky + l.fy) / 2, l.fx, l.fy - 1.4 * u, col, 3.4 * u);
        shoe(l.fx, l.fy);
      };
      const shX = Math.sin(P.lean) * 11 * u, shY = -Math.cos(P.lean) * 11 * u;
      const arm = (e, col) => {
        limb(shX, shY, (shX + e[0]) / 2 + 0.8 * u, (shY + e[1]) / 2 + 0.8 * u, e[0], e[1], col, 2.8 * u);
        ctx.fillStyle = lk.skin; disc(ctx, e[0], e[1], 1.45 * u);
      };
      const hx = Math.sin(P.lean) * 17.5 * u, hy = -Math.cos(P.lean) * 17.5 * u;
      if (lk.style === 'long' || lk.style === 'pony') hairBackSide(p, P, u, hx, hy, now);
      if (lk.bag) { ctx.save(); ctx.rotate(P.lean); ctx.fillStyle = css(mix(hex(lk.prop), [0, 0, 0], 0.15)); rrect(ctx, -7.4 * u, -12 * u, 4 * u, 8.4 * u, 1.6 * u); ctx.fill(); ctx.restore(); }
      leg(-0.8 * u, P.legB, pantsD);
      arm(P.armB, shirtD);
      ctx.save(); ctx.rotate(P.lean);
      ctx.fillStyle = css(shirt); rrect(ctx, -4.4 * u, -13 * u, 8.8 * u, 13.6 * u, 3.8 * u); ctx.fill();
      ctx.fillStyle = css(pants); rrect(ctx, -4.4 * u, -2.4 * u, 8.8 * u, 3.4 * u, 1.4 * u); ctx.fill();
      if (lk.bag) { ctx.strokeStyle = css(mix(hex(lk.prop), [0, 0, 0], 0.3)); ctx.lineWidth = 1 * u; ctx.beginPath(); ctx.moveTo(-3.6 * u, -12.6 * u); ctx.lineTo(0.6 * u, -5 * u); ctx.stroke(); }
      if (lk.acc === 'scarf') { ctx.fillStyle = lk.scarf; rrect(ctx, -4 * u, -13.6 * u, 8.4 * u, 2.8 * u, 1.4 * u); ctx.fill(); rrect(ctx, 1.6 * u, -12 * u, 2.4 * u, 6 * u, 1 * u); ctx.fill(); }
      ctx.restore();
      leg(0.8 * u, P.legF, css(pants));
      headSide(p, P, u, hx, hy);
      if (P.prop === 'book') {
        const bx = (P.armB[0] + P.armF[0]) / 2 + 0.6 * u, by = (P.armB[1] + P.armF[1]) / 2 - 0.4 * u;
        ctx.save(); ctx.translate(bx, by); ctx.rotate(-0.25);
        ctx.fillStyle = lk.prop; rrect(ctx, -3.4 * u, -2.6 * u, 6.8 * u, 4.6 * u, 0.6 * u); ctx.fill();
        ctx.fillStyle = '#FFF8EE'; rrect(ctx, -3 * u, -3 * u, 2.9 * u, 4 * u, 0.4 * u); ctx.fill(); rrect(ctx, 0.1 * u, -3 * u, 2.9 * u, 4 * u, 0.4 * u); ctx.fill();
        if (P.page >= 0) { ctx.fillStyle = '#F1E6D6'; const w = 2.9 * u * Math.cos(P.page * Math.PI); rrect(ctx, Math.min(0, w), -3.2 * u, Math.abs(w), 4 * u, 0.4 * u); ctx.fill(); }
        ctx.restore();
      }
      arm(P.armF, css(shirt));
      drawHandProp(P.prop, P.armF, lk, u);
      if (P.dizzy) dizzyStars(hx, hy - 7 * u, u, now);
    }

    function drawHandProp(prop, h, lk, u) {
      if (prop === 'phone') { ctx.fillStyle = '#2A2527'; rrect(ctx, h[0] - 0.6 * u, h[1] - 3 * u, 2 * u, 4.2 * u, 0.6 * u); ctx.fill(); ctx.fillStyle = lk.skin; disc(ctx, h[0], h[1], 1.45 * u); }
      if (prop === 'cup') {
        ctx.fillStyle = '#FFF8EE'; rrect(ctx, h[0] - 1.4 * u, h[1] - 3.6 * u, 2.8 * u, 3.8 * u, 0.6 * u); ctx.fill();
        ctx.fillStyle = lk.prop; ctx.fillRect(h[0] - 1.4 * u, h[1] - 2.4 * u, 2.8 * u, 1.2 * u);
        ctx.fillStyle = lk.skin; disc(ctx, h[0], h[1], 1.45 * u);
      }
    }

    function dizzyStars(x, y, u, now) {
      ctx.fillStyle = '#FFD45C';
      for (let i = 0; i < 3; i++) {
        const a = now / 300 + i * TAU / 3, sx = x + Math.cos(a) * 5 * u, sy = y + Math.sin(a) * 1.6 * u;
        ctx.beginPath();
        for (let j = 0; j < 10; j++) { const r = j % 2 ? 0.6 * u : 1.5 * u, b = j * Math.PI / 5 - Math.PI / 2; ctx.lineTo(sx + Math.cos(b) * r, sy + Math.sin(b) * r); }
        ctx.closePath(); ctx.fill();
      }
    }

    function hairBackSide(p, P, u, hx, hy, now) {
      const lk = p.look, flick = (P.hair || 0) * 3 * u;
      ctx.fillStyle = lk.hair;
      if (lk.style === 'long') { rrect(ctx, hx - 6.6 * u - flick, hy - 2 * u, 7.4 * u, 12 * u, 3 * u); ctx.fill(); }
      else { const sw = Math.sin(now / 260 + p.seed) * 0.8 * u; disc(ctx, hx - 6.6 * u + sw - flick, hy - 0.6 * u, 2.6 * u); disc(ctx, hx - 7.8 * u + sw * 1.6 - flick, hy + 2.6 * u, 2 * u); }
    }

    function eyes(P, x, y, u, dark) {
      if (P.eyes === 'open') { ctx.fillStyle = dark; disc(ctx, x, y, 0.62 * u); }
      else if (P.eyes === 'swirl') { ctx.strokeStyle = dark; ctx.lineWidth = 0.5 * u; ctx.beginPath(); ctx.arc(x, y, 0.9 * u, 0, TAU * 0.8); ctx.stroke(); }
      else { ctx.strokeStyle = dark; ctx.lineWidth = 0.7 * u; ctx.beginPath(); ctx.moveTo(x - 0.8 * u, y + 0.1 * u); ctx.lineTo(x + 0.8 * u, y + 0.1 * u); ctx.stroke(); }
    }

    function headSide(p, P, u, hx, hy) {
      const lk = p.look, dark = '#2A2527';
      ctx.save(); ctx.translate(hx, hy); ctx.rotate(P.head);
      ctx.fillStyle = lk.hair;
      if (lk.style === 'bob') { rrect(ctx, -6.6 * u, -6 * u, 11.4 * u, 11.6 * u, 5 * u); ctx.fill(); }
      else disc(ctx, -1.1 * u, -0.2 * u, 5.5 * u);
      if (lk.style === 'curly') for (let a = 2.6; a < 6.4; a += 0.62) disc(ctx, Math.cos(a) * 5 * u - 0.6 * u, Math.sin(a) * 5 * u - 0.4 * u, 2.3 * u);
      if (lk.style === 'buns') { disc(ctx, -3.2 * u, -5.6 * u, 2.4 * u); disc(ctx, 1.6 * u, -6.2 * u, 2.4 * u); }
      ctx.fillStyle = lk.skin; disc(ctx, 0.6 * u, 0.4 * u, 5 * u);
      hatOrFringe(lk, u, 'side');
      if (lk.acc === 'bow') { ctx.fillStyle = '#FF7AA8'; disc(ctx, -3.6 * u, -4.6 * u, 1.6 * u); disc(ctx, -1.6 * u, -5.6 * u, 1.6 * u); }
      eyes(P, 3.4 * u, 0.9 * u, u, dark);
      ctx.fillStyle = 'rgba(240,120,110,0.45)'; disc(ctx, 2.5 * u, 2.7 * u, 1.1 * u);
      if (lk.freckles) { ctx.fillStyle = 'rgba(150,90,60,0.5)'; disc(ctx, 2 * u, 2.1 * u, 0.3 * u); disc(ctx, 3 * u, 2.4 * u, 0.3 * u); }
      mouth(P, 4 * u, 3.2 * u, 3.7 * u, 2.6 * u, u, dark);
      if (lk.acc === 'glasses') { ctx.strokeStyle = dark; ctx.lineWidth = 0.6 * u; ctx.beginPath(); ctx.arc(3.4 * u, 0.9 * u, 1.6 * u, 0, TAU); ctx.moveTo(1.8 * u, 0.6 * u); ctx.lineTo(-1.6 * u, 0.2 * u); ctx.stroke(); }
      if (lk.acc === 'phones') {
        ctx.strokeStyle = dark; ctx.lineWidth = 1.2 * u; ctx.beginPath(); ctx.arc(-0.6 * u, 0, 6.4 * u, Math.PI * 1.08, Math.PI * 1.92); ctx.stroke();
        ctx.fillStyle = lk.hat; rrect(ctx, -3.2 * u, -0.6 * u, 3.2 * u, 4.4 * u, 1.2 * u); ctx.fill();
      }
      ctx.restore();
    }

    function mouth(P, ox, oy, sx, sy, u, dark) {
      if (P.mouth === 'o') { ctx.fillStyle = '#7A2E2E'; disc(ctx, ox, oy, 0.75 * u); }
      else if (P.mouth === 'smile') { ctx.strokeStyle = dark; ctx.lineWidth = 0.55 * u; ctx.beginPath(); ctx.arc(sx, sy, 0.9 * u, 0.2, Math.PI - 0.6); ctx.stroke(); }
    }

    // hats and fringes; view 'side' leans the shapes forward (+x), 'front' keeps them centered
    function hatOrFringe(lk, u, view) {
      const side = view === 'side';
      if (lk.style === 'cap') {
        ctx.fillStyle = lk.hat; ctx.beginPath(); ctx.arc(0, -0.8 * u, 5.7 * u, Math.PI, TAU); ctx.fill();
        if (side) rrect(ctx, 0, -1.8 * u, 8.4 * u, 1.8 * u, 0.9 * u); else rrect(ctx, -4.6 * u, -1.6 * u, 9.2 * u, 2 * u, 1 * u);
        ctx.fill();
      } else if (lk.style === 'beanie') {
        ctx.fillStyle = lk.hat; ctx.beginPath(); ctx.arc(0, -0.6 * u, 5.8 * u, Math.PI, TAU); ctx.fill();
        ctx.fillStyle = css(mix(hex(lk.hat), [255, 255, 255], 0.3)); rrect(ctx, -6 * u, -1.8 * u, 12 * u, 2.2 * u, 1 * u); ctx.fill(); disc(ctx, side ? -0.4 * u : 0, -7 * u, 1.8 * u);
      } else if (lk.style === 'spiky') {
        ctx.fillStyle = lk.hair; ctx.beginPath(); ctx.moveTo(-5.4 * u, -0.6 * u);
        for (let i = 0; i <= 5; i++) { const a = Math.PI + i / 5 * Math.PI * 0.95; ctx.lineTo(Math.cos(a) * 7.4 * u, Math.sin(a) * 7.4 * u - 0.6 * u); ctx.lineTo(Math.cos(a + 0.3) * 5 * u, Math.sin(a + 0.3) * 5 * u - 0.6 * u); }
        ctx.closePath(); ctx.fill();
      } else if (lk.style !== 'curly') {
        ctx.fillStyle = lk.hair; ctx.beginPath();
        if (side) { ctx.arc(0.2 * u, -0.2 * u, 5.4 * u, Math.PI * 1.02, Math.PI * 1.9); ctx.quadraticCurveTo(1.6 * u, -2.6 * u, -2 * u, -1.4 * u); }
        else { ctx.arc(0, -0.2 * u, 5.4 * u, Math.PI * 1.02, Math.PI * 1.98); ctx.quadraticCurveTo(1.4 * u, -3.2 * u, 0, -1.6 * u); ctx.quadraticCurveTo(-1.4 * u, -3.2 * u, -5.3 * u, -0.6 * u); }
        ctx.closePath(); ctx.fill();
      }
    }

    function drawFront(p, L, now, u, up) {
      const P = frontPose(p, p.act, now, u), lk = p.look, dark = '#2A2527';
      const shirt = hex(lk.shirt), shirtD = css(mix(shirt, [0, 0, 0], 0.18)), pants = css(hex(lk.pants));
      shadow(P.dx, 0.6 * u, 6.4 * u);
      ctx.translate(P.dx, -up + P.hipY);
      // legs and shoes
      for (const s of [-1, 1]) {
        const lift = (s < 0 ? P.liftL : P.liftR) + (s > 0 ? P.tapR : 0), fx = s * 1.9 * u, fy = 9 * u - lift;
        limb(s * 1.7 * u, 0, s * 2 * u, 4.4 * u - lift * 0.5, fx, fy - 1.2 * u, pants, 3.4 * u);
        ctx.fillStyle = lk.shoes; rrect(ctx, fx - 1.9 * u, fy - 2.4 * u, 3.8 * u, 2.6 * u, 1.2 * u); ctx.fill();
      }
      if (lk.style === 'long') { ctx.fillStyle = lk.hair; rrect(ctx, -6.4 * u, -23 * u + (P.hair || 0) * u, 12.8 * u, 14 * u, 4.5 * u); ctx.fill(); }
      // torso
      ctx.fillStyle = css(shirt); rrect(ctx, -4.6 * u, -13 * u, 9.2 * u, 13.6 * u, 3.8 * u); ctx.fill();
      ctx.fillStyle = pants; rrect(ctx, -4.6 * u, -2.4 * u, 9.2 * u, 3.4 * u, 1.4 * u); ctx.fill();
      if (lk.bag) { ctx.strokeStyle = css(mix(hex(lk.prop), [0, 0, 0], 0.3)); ctx.lineWidth = 1 * u; ctx.beginPath(); ctx.moveTo(-3.4 * u, -12.6 * u); ctx.lineTo(3.4 * u, -4.4 * u); ctx.stroke(); }
      if (lk.acc === 'scarf') { ctx.fillStyle = lk.scarf; rrect(ctx, -4.4 * u, -13.6 * u, 8.8 * u, 2.8 * u, 1.4 * u); ctx.fill(); rrect(ctx, 1 * u, -12 * u, 2.4 * u, 5.4 * u, 1 * u); ctx.fill(); }
      // arms (a shade darker so they read against the shirt)
      for (const [s, h] of [[-1, P.armL], [1, P.armR]]) {
        const sx = s * 4 * u, sy = -11.4 * u;
        limb(sx, sy, (sx + h[0]) / 2 + s * 1 * u, (sy + h[1]) / 2, h[0], h[1], shirtD, 2.8 * u);
        ctx.fillStyle = lk.skin; disc(ctx, h[0], h[1], 1.45 * u);
      }
      drawHandProp(P.prop, P.armR, lk, u);
      // head
      ctx.save(); ctx.translate(0, -17.5 * u + P.headY); ctx.rotate(P.head);
      ctx.fillStyle = lk.hair;
      if (lk.style === 'bob') { rrect(ctx, -6.2 * u, -6 * u, 12.4 * u, 11.4 * u, 5 * u); ctx.fill(); }
      else disc(ctx, 0, -0.6 * u, 5.7 * u);
      if (lk.style === 'curly') for (let a = 3.0; a < 6.5; a += 0.5) disc(ctx, Math.cos(a) * 5.2 * u, Math.sin(a) * 5 * u - 0.4 * u, 2.2 * u);
      if (lk.style === 'buns') { disc(ctx, -4.2 * u, -5 * u, 2.3 * u); disc(ctx, 4.2 * u, -5 * u, 2.3 * u); }
      if (lk.style === 'pony') { const sw = Math.sin(now / 260 + p.seed) * 0.8 * u; disc(ctx, 5.8 * u + sw, 1.6 * u, 2 * u); }
      ctx.fillStyle = lk.skin; disc(ctx, 0, 0.5 * u, 5 * u);
      hatOrFringe(lk, u, 'front');
      if (lk.acc === 'bow') { ctx.fillStyle = '#FF7AA8'; disc(ctx, 3 * u, -5 * u, 1.5 * u); disc(ctx, 5 * u, -4.2 * u, 1.5 * u); }
      eyes(P, -1.8 * u, 0.9 * u, u, dark); eyes(P, 1.8 * u, 0.9 * u, u, dark);
      ctx.fillStyle = 'rgba(240,120,110,0.45)'; disc(ctx, -3 * u, 2.5 * u, 1 * u); disc(ctx, 3 * u, 2.5 * u, 1 * u);
      if (lk.freckles) { ctx.fillStyle = 'rgba(150,90,60,0.5)'; for (const s of [-1, 1]) { disc(ctx, s * 2.6 * u, 1.9 * u, 0.3 * u); disc(ctx, s * 3.4 * u, 2.2 * u, 0.3 * u); } }
      mouth(P, 0, 3 * u, 0, 2.4 * u, u, dark);
      if (lk.acc === 'glasses') { ctx.strokeStyle = dark; ctx.lineWidth = 0.6 * u; ctx.beginPath(); ctx.arc(-1.8 * u, 0.9 * u, 1.5 * u, 0, TAU); ctx.moveTo(0.3 * u, 0.9 * u); ctx.arc(1.8 * u, 0.9 * u, 1.5 * u, Math.PI, Math.PI * 3); ctx.stroke(); }
      if (lk.acc === 'phones') {
        ctx.strokeStyle = dark; ctx.lineWidth = 1.2 * u; ctx.beginPath(); ctx.arc(0, 0, 6.3 * u, Math.PI * 1.02, Math.PI * 1.98); ctx.stroke();
        ctx.fillStyle = lk.hat; rrect(ctx, -6.8 * u, -1.6 * u, 2.4 * u, 4.4 * u, 1.1 * u); ctx.fill(); rrect(ctx, 4.4 * u, -1.6 * u, 2.4 * u, 4.4 * u, 1.1 * u); ctx.fill();
      }
      ctx.restore();
    }

    function drawFx(C, s) {
      for (const f of crowd.fx) {
        const e = f.t / f.life, a = Math.sin(Math.PI * Math.min(1, e * 1.2)), y = f.y - e * 16;
        ctx.globalAlpha = a;
        if (f.type === 'heart') {
          ctx.fillStyle = '#FF6F91'; const x = f.x + Math.sin(e * 6) * 3;
          disc(ctx, x - 1.6 * s, y, 1.8 * s); disc(ctx, x + 1.6 * s, y, 1.8 * s);
          ctx.beginPath(); ctx.moveTo(x - 3.3 * s, y + 0.6 * s); ctx.lineTo(x + 3.3 * s, y + 0.6 * s); ctx.lineTo(x, y + 4.2 * s); ctx.closePath(); ctx.fill();
        } else if (f.type === 'note') {
          ctx.fillStyle = css(mix(hex(f.c), [0, 0, 0], 0.25)); const x = f.x + Math.sin(e * 5) * 4;
          ctx.beginPath(); ctx.ellipse(x, y, 1.9 * s, 1.4 * s, -0.4, 0, TAU); ctx.fill();
          ctx.fillRect(x + 1.3 * s, y - 6 * s, 0.8 * s, 6 * s); ctx.fillRect(x + 1.3 * s, y - 6 * s, 2.6 * s, 1.2 * s);
        } else if (f.type === 'z') {
          drawPix('z', f.x + e * 8, y - e * 6, 10 + Math.round(e * 4), 2, css(C.ink, 0.7), 800);
        } else if (f.type === 'bang') {
          drawPix('!', f.x, f.y - e * 6, 12, 2, css(C.ink, 0.85), 800);
        } else if (f.type === 'dots') {
          ctx.fillStyle = 'rgba(255,255,255,0.92)'; rrect(ctx, f.x - 6 * s, f.y - 3 * s, 12 * s, 6 * s, 3 * s); ctx.fill();
          ctx.fillStyle = '#6B6168'; for (let i = -1; i <= 1; i++) if (f.t * 3 % 3 >= i + 1) disc(ctx, f.x + i * 3.2 * s, f.y, 0.9 * s);
        } else if (f.type === 'drop') {
          ctx.fillStyle = '#8EC9F2'; const x = f.x - e * 4;
          ctx.beginPath(); ctx.moveTo(x, y - 2.4 * s); ctx.quadraticCurveTo(x + 1.6 * s, y, x, y + 1.2 * s); ctx.quadraticCurveTo(x - 1.6 * s, y, x, y - 2.4 * s); ctx.fill();
        } else if (f.type === 'spark') {
          ctx.strokeStyle = '#FFF4C2'; ctx.lineWidth = 1.2 * s; const r = (3 + e * 6) * s;
          ctx.beginPath();
          for (let i = 0; i < 8; i++) { const b = i / 8 * TAU; ctx.moveTo(f.x + Math.cos(b) * r * 0.5, f.y + Math.sin(b) * r * 0.5); ctx.lineTo(f.x + Math.cos(b) * r, f.y + Math.sin(b) * r); }
          ctx.stroke();
        }
      }
      ctx.globalAlpha = 1;
    }

    function draw(L, C, now) {
      if (S.opts.transparent || !crowd.people.length && !crowd.fx.length) return;
      ctx = S.ctx;
      const order = crowd.people.slice().sort((a, b) => a.y - b.y);
      for (const p of order) drawPerson(p, L, now);
      drawFx(C, clamp(unitOf(L), 1.2, 3));
    }

    // where the song info is, so nobody stands in front of it
    function setHud(box) { crowd.hud = box; }

    return { update, draw, setHud };
  };
})();
