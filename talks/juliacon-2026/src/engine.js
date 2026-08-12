/* ==========================================================================
   Given an Oracle for f — deck engine
   Vanilla JS, no external requests, runs from file://.
   Defensive by construction: a missing component, a missing <template>, a
   backup slide that does not exist, a browser without requestFullscreen —
   none of these may ever throw. A deck that dies on stage is a deck that
   lost the talk.
   ========================================================================== */
(function () {
  'use strict';

  /* ---- tiny helpers ---------------------------------------------------- */
  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  };
  var warn = function () {
    try { console.warn.apply(console, arguments); } catch (e) {}
  };

  /* ---- flags ----------------------------------------------------------- */
  var STILL = /[?&]still\b/.test(location.href);
  var REDUCED = (function () {
    try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; }
    catch (e) { return false; }
  }());

  /* ---- timer checkpoints ----------------------------------------------- */
  /* s6 closes part 1 (the why); s9 is the Bennett animation; s13 the oracle
     beat; s15 the close. */
  var CHECKPOINTS = [
    { slide: 's6',  t: 5 * 60 },
    { slide: 's9',  t: 8 * 60 },
    { slide: 's13', t: 11 * 60 + 30 },
    { slide: 's15', t: 14 * 60 }
  ];

  /* ---- DOM ------------------------------------------------------------- */
  var stage, band, bandState, bandOut, counter, timerEl, notesEl, helpEl,
      progressEl;
  var slides = [], linear = [], order = [], byId = {};

  /* ---- state ----------------------------------------------------------- */
  var idx = 0;              // index into `order` — the last LINEAR slide
  var currentId = null;     // may be a backup id
  var onBackup = false;
  var t0 = null;            // timer origin; null = not started
  var timerShown = false;
  var notesShown = false;
  var helpShown = false;
  var shadowOn = false;
  var shadowRAF = 0;

  /* ======================================================================
     components
     ====================================================================== */
  function registry() { return window.DeckComponents || {}; }

  function compsIn(el) { return el ? $$('[data-component]', el) : []; }

  function callComp(el, fn, arg) {
    var name = el.getAttribute('data-component');
    var c = registry()[name];
    if (!c || typeof c[fn] !== 'function') return undefined;
    try {
      return arg === undefined ? c[fn](el) : c[fn](el, arg);
    } catch (e) {
      warn('[deck] component "' + name + '".' + fn + ' threw:', e);
      return undefined;
    }
  }

  function mountAll() {
    $$('[data-component]').forEach(function (el) {
      el._k = 0;
      callComp(el, 'mount');
    });
  }

  /* ======================================================================
     chrome
     ====================================================================== */
  function shownBuilds(el) {
    return $$('.build', el).filter(function (b) {
      return b.classList.contains('shown');
    });
  }

  function linearIndexOf(id) { return order.indexOf(id); }

  function updateBand(el) {
    if (!band) return;
    var state = (el && el.getAttribute('data-band')) || 'off';
    if (state !== 'live' && state !== 'shadow' && state !== 'off') state = 'off';
    band.setAttribute('data-state', state);
    if (!bandState) return;
    bandState.textContent =
      state === 'live' ? '● LIVE' :
      state === 'shadow' ? 'shadow output — press D' : '';
  }

  function updateCounter() {
    if (!counter) return;
    counter.textContent = onBackup
      ? (currentId || 'backup')
      : ((idx + 1) + '/' + Math.max(order.length, 1));
  }

  function updateProgress() {
    if (!progressEl) return;
    var frac = order.length ? (idx + 1) / order.length : 0;
    progressEl.style.width = (frac * 100).toFixed(2) + '%';
  }

  function updateNotes(el) {
    if (!notesEl) return;
    notesEl.textContent = (el && el.getAttribute('data-notes')) || '';
  }

  function updateChrome() {
    var el = byId[currentId];
    updateBand(el);
    updateCounter();
    updateProgress();
    updateNotes(el);
    updateTimer();
  }

  /* ======================================================================
     code auto-fit — "text must never overflow" is a hard constraint, and
     the slide author cannot know the rendered advance width of JuliaMono vs
     the fallback. Shrink only, never grow past the CSS size.
     ====================================================================== */
  function fitCode(el) {
    if (!el) return;
    $$('pre', el).forEach(function (p) {
      /* The AUTHORED size is the ceiling. Cache the author's inline
         font-size string once — '' means "whatever the stylesheet says" —
         and restore it before every fit. Caching the STRING (which may be
         '2.2cqh') rather than a resolved px value keeps the slide
         responsive: a resize re-resolves the author's units, then shrinks
         from there if it still does not fit. Blindly clearing the inline
         size, as this once did, silently promoted a deliberately small
         pre back up to var(--f-code). */
      if (p.dataset.fitBase === undefined) p.dataset.fitBase = p.style.fontSize || '';
      var base = p.dataset.fitBase;
      if (p.style.fontSize !== base) p.style.fontSize = base;
      if (!p.clientWidth) return;
      var fs = parseFloat(window.getComputedStyle(p).fontSize) || 0;
      if (!fs) return;
      var guard = 0;
      while (p.scrollWidth > p.clientWidth + 1 && fs > 8 && guard++ < 60) {
        fs -= 0.5;
        p.style.fontSize = fs + 'px';
      }
    });
  }

  function markLongCode() {
    $$('pre').forEach(function (p) {
      var lines = (p.textContent || '').replace(/\s+$/, '').split('\n').length;
      if (lines > 10) p.classList.add('long');
    });
  }

  /* ======================================================================
     printing / PDF export
     Print CSS lays every slide out at once, but a printed slide is a STILL:
     nothing will ever press space on it. Without this, a PDF made from the
     live deck (i.e. without ?still) shows costbars with zero-width fills and
     the stepper parked at gate 0 — the slides that carry the numbers print
     empty. So: reveal every build and drive every component to its end
     state, exactly as ?still does. There is no afterprint restore: the deck
     is simply left at its final state, which is a state the speaker can keep
     presenting from (and reverse out of).
     ====================================================================== */
  function stillEverything() {
    $$('.build').forEach(function (b) { b.classList.add('shown'); });
    $$('[data-component]').forEach(function (c) {
      callComp(c, 'onStill');
      c._k = Number.MAX_SAFE_INTEGER;      // already at its end state
    });
    slides.forEach(fitCode);
    updateChrome();
  }

  function installPrintHooks() {
    try {
      window.addEventListener('beforeprint', stillEverything);
    } catch (e) { warn('[deck] beforeprint unavailable:', e); }
    /* Safari never fires beforeprint; the print media query does. */
    try {
      var mq = window.matchMedia('print');
      var onMQ = function (e) { if (e.matches) stillEverything(); };
      if (mq.addEventListener) mq.addEventListener('change', onMQ);
      else if (mq.addListener) mq.addListener(onMQ);
    } catch (e) {}
  }

  /* ======================================================================
     shadow terminal
     ====================================================================== */
  function clearShadow() {
    if (shadowRAF) { cancelAnimationFrame(shadowRAF); shadowRAF = 0; }
    if (bandOut) bandOut.textContent = '';
    shadowOn = false;
  }

  function templateText(el) {
    var tpl = el ? el.querySelector('template.shadow-term') : null;
    if (!tpl) return null;
    var txt = (tpl.content && tpl.content.textContent != null)
      ? tpl.content.textContent : tpl.textContent;
    if (txt == null) return null;
    var lines = txt.replace(/^\n+/, '').replace(/\s+$/, '').split('\n');
    // strip the common indent the HTML author had to type
    var pad = Infinity;
    lines.forEach(function (l) {
      if (!l.trim()) return;
      var m = l.match(/^[ \t]*/);
      pad = Math.min(pad, m ? m[0].length : 0);
    });
    if (!isFinite(pad)) pad = 0;
    return lines.map(function (l) { return l.slice(pad); });
  }

  function showShadow() {
    if (!bandOut) return;
    var lines = templateText(byId[currentId]);
    if (!lines || !lines.length) {
      warn('[deck] no <template class="shadow-term"> on', currentId);
      return;                              // never throw, never blank the band
    }
    bandOut.textContent = '';
    var model = lines.map(function (text) {
      var m = text.match(/^(\s*julia>\s?)([\s\S]*)$/);
      var head = m ? m[1] : '';
      var rest = m ? m[2] : text;
      var line = document.createElement('div');
      line.className = 'term-line';
      var hs = document.createElement('span');
      hs.className = 'term-prompt';
      var ts = document.createElement('span');
      ts.className = 'term-text';
      line.appendChild(hs);
      line.appendChild(ts);
      bandOut.appendChild(line);
      return { head: head, rest: rest, hs: hs, ts: ts };
    });
    var total = model.reduce(function (a, m) { return a + m.head.length + m.rest.length; }, 0);

    function paint(n) {
      var left = n;
      model.forEach(function (m) {
        var h = Math.max(0, Math.min(m.head.length, left)); left -= h;
        var r = Math.max(0, Math.min(m.rest.length, left)); left -= r;
        m.hs.textContent = m.head.slice(0, h);
        m.ts.textContent = m.rest.slice(0, r);
      });
    }

    shadowOn = true;
    if (REDUCED || STILL) { paint(total); return; }
    var n = 0;
    (function tick() {
      n += 24;                              // ~24 chars per frame
      paint(n);
      if (n < total) shadowRAF = requestAnimationFrame(tick);
      else shadowRAF = 0;
    }());
  }

  function toggleShadow() {
    if (shadowOn) clearShadow(); else showShadow();
  }

  /* ======================================================================
     timer HUD
     ====================================================================== */
  function elapsed() { return t0 === null ? 0 : Math.floor((Date.now() - t0) / 1000); }

  function startTimer() { if (t0 === null && !STILL) t0 = Date.now(); }

  function lateness() {
    if (t0 === null) return 0;
    var e = elapsed(), worst = 0;
    CHECKPOINTS.forEach(function (cp) {
      var j = linearIndexOf(cp.slide);
      if (j < 0) return;
      if (idx >= j) return;                 // checkpoint made
      if (e > cp.t) worst = Math.max(worst, e - cp.t);
    });
    return worst;
  }

  function updateTimer() {
    if (!timerEl) return;
    var e = elapsed();
    var mm = Math.floor(e / 60), ss = e % 60;
    timerEl.textContent = (mm < 10 ? '0' : '') + mm + ':' + (ss < 10 ? '0' : '') + ss;
    var late = lateness();
    timerEl.setAttribute('data-late', late > 30 ? 'hard' : (late > 0 ? 'soft' : 'none'));
  }

  function toggleTimer() {
    if (STILL) return;                      // timers off for screenshots
    timerShown = !timerShown;
    if (timerEl) timerEl.hidden = !timerShown;
    updateTimer();
  }

  function resetTimer() {
    t0 = null;
    updateTimer();
  }

  /* ======================================================================
     navigation
     ====================================================================== */
  function setHash(id) {
    if (!id) return;
    var want = '#' + id;
    if (location.hash === want) return;
    try {
      history.replaceState(null, '', want);
    } catch (e) {
      try { location.hash = id; } catch (e2) {}   // file:// in some browsers
    }
  }

  function restartSMIL(el) {
    $$('svg.smil', el).forEach(function (svg) {
      try { svg.setCurrentTime(0); } catch (e) {}
    });
    if (el && el.matches && el.matches('svg.smil')) {
      try { el.setCurrentTime(0); } catch (e) {}
    }
  }

  /**
   * Enter a slide by id.
   * opts.build: 'none' (default — fresh) | 'all' (arriving backwards / still)
   * opts.force: re-enter even if it is already current
   */
  function enter(id, opts) {
    opts = opts || {};
    var el = byId[id];
    if (!el) { warn('[deck] no slide "' + id + '"'); return; }
    if (id === currentId && !opts.force) { updateChrome(); return; }

    var prev = byId[currentId];
    if (prev && prev !== el) {
      compsIn(prev).forEach(function (c) { callComp(c, 'onLeave'); });
      prev.classList.remove('current');
    }

    clearShadow();

    currentId = id;
    onBackup = el.classList.contains('backup');
    if (!onBackup) {
      var j = linearIndexOf(id);
      if (j >= 0) idx = j;
    }
    el.classList.add('current');

    var all = STILL || opts.build === 'all';
    $$('.build', el).forEach(function (b) {
      if (all) b.classList.add('shown'); else b.classList.remove('shown');
    });

    compsIn(el).forEach(function (c) {
      c._k = 0;
      callComp(c, 'onEnter');
      if (all) {
        callComp(c, 'onStill');
        c._k = Number.MAX_SAFE_INTEGER;    // already at its end state
      }
    });

    restartSMIL(el);
    fitCode(el);
    updateChrome();
    setHash(id);

    Deck.enterHooks.forEach(function (fn) {
      try { fn(el, id, idx); } catch (e) { warn('[deck] enterHook threw:', e); }
    });
  }

  function go(i) {
    if (!order.length) return;
    i = Math.max(0, Math.min(order.length - 1, i | 0));
    enter(order[i]);
  }

  function advance() {
    startTimer();
    var el = byId[currentId];
    if (!el) return;

    // 1. a component on this slide may CONSUME the advance.
    //    k is "consumed steps so far + 1", so it only increases when the
    //    component says true. A component that has finished will therefore
    //    see the SAME rejected k again on every later advance — returning
    //    false for it must stay idempotent.
    var cs = compsIn(el);
    for (var i = 0; i < cs.length; i++) {
      var c = cs[i];
      var k = (c._k || 0) + 1;
      if (callComp(c, 'onStep', k) === true) {
        c._k = k;
        updateChrome();
        return;
      }
    }

    // 2. otherwise reveal the next build
    var builds = $$('.build', el);
    for (var b = 0; b < builds.length; b++) {
      if (!builds[b].classList.contains('shown')) {
        builds[b].classList.add('shown');
        fitCode(el);
        updateChrome();
        return;
      }
    }

    // 3. otherwise move on. From a backup we stay put — an accidental space
    //    during Q&A must not yank the speaker out of the slide they are on
    //    (B is the documented way back).
    if (onBackup) return;
    if (idx < order.length - 1) enter(order[idx + 1]);
  }

  function reverse() {
    var el = byId[currentId];
    if (!el) return;

    // builds unwind first — they were revealed last
    var shown = shownBuilds(el);
    if (shown.length) {
      shown[shown.length - 1].classList.remove('shown');
      updateChrome();
      return;
    }

    // then components rewind to their start (no onBack in the contract)
    var live = compsIn(el).filter(function (c) { return (c._k || 0) > 0; });
    if (live.length) {
      live.forEach(function (c) { c._k = 0; callComp(c, 'onEnter'); });
      updateChrome();
      return;
    }

    if (onBackup) { enter(order[idx], { build: 'all', force: true }); return; }
    if (idx > 0) enter(order[idx - 1], { build: 'all' });
  }

  function gotoBackup(id) {
    if (byId[id]) enter(id);
    else warn('[deck] backup "' + id + '" is not in this build');
  }

  function backToLinear() {
    if (!onBackup) return;
    enter(order[idx] || order[0], { build: 'all', force: true });
  }

  /* ======================================================================
     overlays
     ====================================================================== */
  function toggleHelp(force) {
    helpShown = (force === undefined) ? !helpShown : !!force;
    if (helpEl) helpEl.hidden = !helpShown;
  }

  function toggleNotes() {
    notesShown = !notesShown;
    if (notesEl) notesEl.hidden = !notesShown;
    updateNotes(byId[currentId]);
  }

  function toggleFullscreen() {
    try {
      var d = document;
      var full = d.fullscreenElement || d.webkitFullscreenElement;
      if (full) {
        (d.exitFullscreen || d.webkitExitFullscreen || function () {}).call(d);
      } else {
        var e = d.documentElement;
        (e.requestFullscreen || e.webkitRequestFullscreen || function () {}).call(e);
      }
    } catch (e) { warn('[deck] fullscreen unavailable:', e); }
  }

  /* ======================================================================
     input
     ====================================================================== */
  function onKey(e) {
    if (e.defaultPrevented) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    var t = e.target;
    if (t && t.closest && t.closest('input, textarea, select, [contenteditable="true"]')) return;

    var k = e.key;

    if (k === 'Escape') {
      if (helpShown) { toggleHelp(false); e.preventDefault(); }
      return;
    }
    if (k === '?') { toggleHelp(); e.preventDefault(); return; }
    if (helpShown) {                       // any other key closes the card
      toggleHelp(false); e.preventDefault(); return;
    }

    switch (k) {
      case 'ArrowRight': case ' ': case 'Spacebar': case 'PageDown':
        advance(); e.preventDefault(); return;
      case 'ArrowLeft': case 'PageUp':
        reverse(); e.preventDefault(); return;
      case 'Home':
        enter(order[0]); e.preventDefault(); return;
      case 'End':
        enter(order[order.length - 1], { build: 'all' }); e.preventDefault(); return;
      case 'f': case 'F':
        toggleFullscreen(); e.preventDefault(); return;
      case 'd': case 'D':
        toggleShadow(); e.preventDefault(); return;
      case 't':
        toggleTimer(); e.preventDefault(); return;
      case 'T':
        resetTimer(); e.preventDefault(); return;
      case 'n': case 'N':
        toggleNotes(); e.preventDefault(); return;
      case '0':
        gotoBackup('fallback'); e.preventDefault(); return;
      case 's': case 'S':
        gotoBackup('stepper'); e.preventDefault(); return;
      case 'b': case 'B':
        backToLinear(); e.preventDefault(); return;
      default:
        return;                            // number keys map nowhere else
    }
  }

  function onClick(e) {
    if (helpShown) { toggleHelp(false); return; }
    var t = e.target;
    if (t && t.closest && t.closest('button, a, input, textarea, select, [data-nav="off"]')) return;
    var r = stage.getBoundingClientRect();
    if (!r.width) return;
    var x = (e.clientX - r.left) / r.width;
    if (x > 2 / 3) advance();
    else if (x < 1 / 3) reverse();
  }

  function onHashChange() {
    var id = (location.hash || '').replace(/^#/, '');
    if (!id || id === currentId) return;
    if (byId[id]) enter(id);
  }

  /* ======================================================================
     boot
     ====================================================================== */
  function init() {
    stage = $('#stage');
    band = $('#band');
    bandState = $('#band-state');
    bandOut = $('#band-out');
    counter = $('#counter');
    timerEl = $('#timer');
    notesEl = $('#notes');
    helpEl = $('#help');
    progressEl = $('#progress');

    slides = $$('section.slide');
    linear = slides.filter(function (s) { return !s.classList.contains('backup'); });
    order = linear.map(function (s, i) {
      if (!s.id) s.id = 'slide-' + i;      // an unnamed slide is still routable
      return s.id;
    });
    slides.forEach(function (s, i) {
      if (!s.id) s.id = 'slide-x-' + i;
      byId[s.id] = s;
    });

    if (!slides.length) { warn('[deck] no slides in this build'); return; }
    if (!order.length) { order = [slides[0].id]; }   // all-backup build: survive

    if (STILL) {
      document.body.classList.add('still');
      $$('.build').forEach(function (b) { b.classList.add('shown'); });
    }

    markLongCode();
    mountAll();

    Deck.order = order;

    var hashId = (location.hash || '').replace(/^#/, '');
    enter(byId[hashId] ? hashId : order[0], { force: true });

    installPrintHooks();

    document.addEventListener('keydown', onKey);
    if (stage) stage.addEventListener('click', onClick);
    window.addEventListener('hashchange', onHashChange);
    window.addEventListener('resize', function () { fitCode(byId[currentId]); });

    if (!STILL) window.setInterval(updateTimer, 250);
  }

  /* ---- public API ------------------------------------------------------ */
  var Deck = {
    order: [],
    enterHooks: [],
    go: go,
    goto: function (id) { enter(id); },
    next: advance,
    prev: reverse,
    still: STILL,
    reduced: REDUCED
  };
  Object.defineProperty(Deck, 'idx', { get: function () { return idx; } });
  Object.defineProperty(Deck, 'current', { get: function () { return currentId; } });
  window.Deck = Deck;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
}());
