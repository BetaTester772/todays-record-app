// TurnTable — record player sounds (spec 6.29)
//
// Small sounds made in code with Web Audio (no recordings): the needle touching down and lifting off, the platter motor
// spinning up and winding down, a record lifted off, slid and set down, and a quiet surface noise (hiss and crackle)
// while the needle is in the groove. Off by default; set up in Settings → Sound.
//
// index.html creates it with TurnTableSound(scene) and calls update(dt, now) every frame. Each sound is a function of
// (audio context, destination, start time), so the same code also renders offline for testing (window.__renderSound).
(() => {
  'use strict';

  // ---------- building blocks ----------
  const noiseCache = new WeakMap();
  // two seconds of white noise, shared per audio context
  function noise(ac) {
    let b = noiseCache.get(ac);
    if (b) return b;
    b = ac.createBuffer(1, ac.sampleRate * 2, ac.sampleRate);
    const d = b.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    noiseCache.set(ac, b);
    return b;
  }
  // Vinyl crackle: sparse clicks of random size, mostly tiny ticks with the odd louder pop, over six seconds (looped).
  function crackleBuffer(ac) {
    const sr = ac.sampleRate, b = ac.createBuffer(1, sr * 6, sr), d = b.getChannelData(0);
    let i = 0;
    while (i < d.length) {
      i += Math.floor(-Math.log(1 - Math.random()) * sr / 14);   // about 14 clicks a second
      const big = Math.random() < 0.06, amp = (big ? 0.6 : 0.12 + Math.random() * 0.22) * (Math.random() < 0.5 ? -1 : 1);
      const len = big ? 40 + Math.random() * 60 : 4 + Math.random() * 14;
      for (let k = 0; k < len && i + k < d.length; k++) d[i + k] += amp * Math.exp(-k / (len / 4)) * (k % 2 ? -0.6 : 1);
    }
    return b;
  }
  const crackleCache = new WeakMap();
  const crackle = ac => crackleCache.get(ac) || (crackleCache.set(ac, crackleBuffer(ac)), crackleCache.get(ac));

  function env(ac, t, peak, attack, decay, dest) {
    const g = ac.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
    g.connect(dest);
    return g;
  }
  function noiseBurst(ac, dest, t, { peak, attack = 0.002, decay, type = 'bandpass', freq = 2000, q = 0.8, offset = Math.random() }) {
    const src = ac.createBufferSource(); src.buffer = noise(ac);
    const f = ac.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    src.connect(f); f.connect(env(ac, t, peak, attack, decay, dest));
    src.start(t, offset, attack + decay + 0.05);
  }
  function thump(ac, dest, t, { peak, from, to, decay }) {
    const o = ac.createOscillator(); o.type = 'sine';
    o.frequency.setValueAtTime(from, t); o.frequency.exponentialRampToValueAtTime(to, t + decay);
    o.connect(env(ac, t, peak, 0.004, decay, dest));
    o.start(t); o.stop(t + decay + 0.05);
  }

  // ---------- the sounds ----------
  const SOUNDS = {
    // the stylus meets the record: a soft low bump, the tick of contact, then a short burst of groove noise
    drop(ac, dest, t) {
      thump(ac, dest, t, { peak: 0.55, from: 95, to: 48, decay: 0.22 });
      noiseBurst(ac, dest, t, { peak: 0.22, decay: 0.03, type: 'highpass', freq: 2500, q: 0.5 });
      noiseBurst(ac, dest, t + 0.015, { peak: 0.09, attack: 0.01, decay: 0.7, type: 'bandpass', freq: 3200, q: 0.6 });
      for (let i = 0; i < 6; i++) noiseBurst(ac, dest, t + 0.05 + Math.random() * 0.55, { peak: 0.06 + Math.random() * 0.1, attack: 0.001, decay: 0.008, type: 'highpass', freq: 3000 });
    },
    // the stylus leaves the groove: a small dry tick and a faint thud from the cue lever
    lift(ac, dest, t) {
      noiseBurst(ac, dest, t, { peak: 0.22, decay: 0.018, type: 'highpass', freq: 3500, q: 0.5 });
      thump(ac, dest, t + 0.01, { peak: 0.18, from: 180, to: 110, decay: 0.08 });
    },
    // the platter motor: a click of the start switch, then a low whirr that rises to speed and fades into silence
    spinUp(ac, dest, t) {
      noiseBurst(ac, dest, t, { peak: 0.1, decay: 0.012, type: 'bandpass', freq: 1800, q: 1.2 });
      thump(ac, dest, t, { peak: 0.1, from: 160, to: 120, decay: 0.05 });
      motor(ac, dest, t + 0.02, 22, 58, 1.3, 0.08);
    },
    // winding down: the whirr sinks in pitch and fades
    spinDown(ac, dest, t) {
      noiseBurst(ac, dest, t, { peak: 0.08, decay: 0.012, type: 'bandpass', freq: 1500, q: 1.2 });
      motor(ac, dest, t + 0.02, 58, 18, 1.6, 0.065);
    },
    // a record lifted off the platter: a soft papery whoosh
    liftRecord(ac, dest, t) { sweep(ac, dest, t, 0.55, 900, 2600, 0.22); },
    // a record slid across: a longer, rising and falling "shhh" with the grain of vinyl on felt
    slide(ac, dest, t) { sweep(ac, dest, t, 1.1, 700, 2200, 0.24, true); },
    // set down on the felt: a muffled thump
    setDown(ac, dest, t) {
      thump(ac, dest, t, { peak: 0.32, from: 120, to: 70, decay: 0.16 });
      noiseBurst(ac, dest, t, { peak: 0.1, attack: 0.003, decay: 0.12, type: 'lowpass', freq: 700, q: 0.5 });
    },
  };
  function motor(ac, dest, t, f0, f1, dur, level) {
    const o = ac.createOscillator(); o.type = 'sawtooth';
    o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(f1, t + dur * 0.55);
    const o2 = ac.createOscillator(); o2.type = 'sine';
    o2.frequency.setValueAtTime(f0 * 2, t); o2.frequency.exponentialRampToValueAtTime(f1 * 2, t + dur * 0.55);
    const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 340; lp.Q.value = 0.7;
    const g = ac.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(level, t + dur * 0.25);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(lp); o2.connect(lp); lp.connect(g); g.connect(dest);
    o.start(t); o2.start(t); o.stop(t + dur + 0.05); o2.stop(t + dur + 0.05);
  }
  function sweep(ac, dest, t, dur, f0, f1, level, grain) {
    const src = ac.createBufferSource(); src.buffer = noise(ac); src.loop = true;
    const bp = ac.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 0.9;
    bp.frequency.setValueAtTime(f0, t);
    bp.frequency.exponentialRampToValueAtTime(f1, t + dur * 0.45);
    bp.frequency.exponentialRampToValueAtTime(f0 * 1.3, t + dur);
    const g = ac.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(level, t + dur * 0.35);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(bp);
    if (grain) {
      // a slow flutter, like the record catching on the felt as it slides
      const am = ac.createGain(), lfo = ac.createOscillator(), depth = ac.createGain();
      lfo.frequency.value = 23; depth.gain.value = 0.35; am.gain.value = 0.65;
      lfo.connect(depth); depth.connect(am.gain); bp.connect(am); am.connect(g);
      lfo.start(t); lfo.stop(t + dur + 0.05);
    } else bp.connect(g);
    g.connect(dest);
    src.start(t, Math.random()); src.stop(t + dur + 0.05);
  }

  // Surface noise while the needle is in the groove: a soft hiss and a little crackle, both through a gain that fades.
  function surface(ac, dest) {
    const hiss = ac.createBufferSource(); hiss.buffer = noise(ac); hiss.loop = true;
    const hp = ac.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 900;
    const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 6500;
    const hg = ac.createGain(); hg.gain.value = 0.04;
    hiss.connect(hp); hp.connect(lp); lp.connect(hg);
    const cr = ac.createBufferSource(); cr.buffer = crackle(ac); cr.loop = true;
    const chp = ac.createBiquadFilter(); chp.type = 'highpass'; chp.frequency.value = 1200;
    const cg = ac.createGain(); cg.gain.value = 0.5;
    cr.connect(chp); chp.connect(cg);
    const out = ac.createGain(); out.gain.value = 0;
    hg.connect(out); cg.connect(out); out.connect(dest);
    hiss.start(); cr.start(0, Math.random() * 6);
    return out;
  }

  window.TurnTableSound = function createSound(S) {
    const opts = () => S.opts.sound || {};
    let ac = null, master = null, bed = null, bedOn = 0;
    const prev = { contact: null, target: null, lifted: false };

    function ensure() {
      if (ac) return true;
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      ac = new AC();
      const comp = ac.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 4;
      master = ac.createGain(); master.connect(comp); comp.connect(ac.destination);
      bed = surface(ac, master);
      return true;
    }
    const enabled = () => !!opts().on && S.role !== 'mirror';
    function play(name, force) {
      if (!(force || enabled()) || !ensure()) return;
      if (window.__soundEvents) window.__soundEvents.push(name);   // test copies only
      if (ac.state === 'suspended') ac.resume();
      SOUNDS[name](ac, master, ac.currentTime + 0.01);
    }

    function update(dt) {
      const o = opts();
      if (!enabled()) { if (ac && bedOn > 0) { bedOn = 0; bed.gain.setTargetAtTime(0, ac.currentTime, 0.1); } return; }
      if (!ensure()) return;
      master.gain.value = Math.pow(clamp01(o.volume ?? 0.5), 1.6) * 0.9;
      const a = S.arm;   // { lift, onRecord, playing, spinTarget, recLift }

      // needle: touching down or lifting off the record
      const contact = a.onRecord && a.lift < 0.03;
      if (prev.contact !== null && o.needle !== false) {
        if (contact && !prev.contact) play('drop');
        else if (!contact && prev.contact && a.lift > 0.03) play('lift');
      }
      prev.contact = contact;

      // motor: the platter starts or stops
      const target = a.spinTarget > 0;
      if (prev.target !== null && target !== prev.target && o.motor !== false) play(target ? 'spinUp' : 'spinDown');
      prev.target = target;

      // the record itself: lifted off, then set down (a slide when it travels sideways)
      const lifted = a.recLift > 0.05;
      if (o.needle !== false) {
        if (lifted && !prev.lifted) play(a.recSlide ? 'slide' : 'liftRecord');
        if (!lifted && prev.lifted) play('setDown');
      }
      prev.lifted = lifted;

      // surface noise while the needle plays the record
      const want = o.noise !== false && contact && a.playing ? 1 : 0;
      if (want !== bedOn && window.__soundEvents) window.__soundEvents.push(want ? 'noise:on' : 'noise:off');
      if (want !== bedOn) { bedOn = want; bed.gain.setTargetAtTime(want, ac.currentTime, want ? 0.35 : 0.12); }
    }
    const clamp01 = v => Math.min(1, Math.max(0, +v || 0));

    // stop everything while the page is paused (screen locked, asleep, covered); pick up again after
    function setPaused(p) { if (ac) { if (p) ac.suspend(); else if (enabled()) ac.resume(); } }

    return { update, setPaused, test: () => play('drop', true), play };
  };

  // For listening: the sounds in the order they happen when a song starts, plays, and the record is changed
  const REEL = [['spinUp', 0.2], ['drop', 1.2], ['surface', 1.5, 3.2], ['lift', 4.9], ['liftRecord', 5.6], ['slide', 6.1], ['setDown', 7.4], ['drop', 8.4], ['surface', 8.6, 10.4], ['lift', 10.6], ['spinDown', 10.9]];
  // For testing: render one sound to a WAV data URL offline, so it can be checked and listened to outside the app.
  window.__renderSound = async (name, seconds = 2.5, volume = 0.5) => {
    const ac = new OfflineAudioContext(1, Math.ceil(44100 * seconds), 44100);
    const comp = ac.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 4;
    const master = ac.createGain(); master.gain.value = Math.pow(volume, 1.6) * 0.9; master.connect(comp); comp.connect(ac.destination);
    if (name === 'surface') { const bed = surface(ac, master); bed.gain.value = 1; }
    else if (name === 'reel') for (const [n, t0, t1] of REEL) {
      if (n === 'surface') { const bed = surface(ac, master); bed.gain.setValueAtTime(0, 0); bed.gain.setTargetAtTime(1, t0, 0.35); bed.gain.setTargetAtTime(0, t1, 0.12); }
      else SOUNDS[n](ac, master, t0);
    }
    else SOUNDS[name](ac, master, 0.05);
    const buf = await ac.startRendering(), d = buf.getChannelData(0);
    let peak = 0, sum = 0; for (const v of d) { peak = Math.max(peak, Math.abs(v)); sum += v * v; }
    const pcm = new DataView(new ArrayBuffer(44 + d.length * 2)), str = (o, s) => [...s].forEach((c, i) => pcm.setUint8(o + i, c.charCodeAt(0)));
    str(0, 'RIFF'); pcm.setUint32(4, 36 + d.length * 2, true); str(8, 'WAVEfmt '); pcm.setUint32(16, 16, true); pcm.setUint16(20, 1, true);
    pcm.setUint16(22, 1, true); pcm.setUint32(24, 44100, true); pcm.setUint32(28, 88200, true); pcm.setUint16(32, 2, true); pcm.setUint16(34, 16, true);
    str(36, 'data'); pcm.setUint32(40, d.length * 2, true);
    for (let i = 0; i < d.length; i++) pcm.setInt16(44 + i * 2, Math.max(-1, Math.min(1, d[i])) * 32767, true);
    let bin = ''; const bytes = new Uint8Array(pcm.buffer); for (let i = 0; i < bytes.length; i += 8192) bin += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return { peak, rms: Math.sqrt(sum / d.length), wav: 'data:audio/wav;base64,' + btoa(bin) };
  };
})();
