/* components.js: "Quantum programming in ordinary Julia" (JuliaCon 2026)
 *
 * Three interactive components for the deck, per DECK-SPEC.md §Components:
 *
 *   costbars  (s8)        the rescaling log-scale cost chart   · 3 consumed steps
 *   entangle  (s11)       the REAL two-branch statevector      · 7 consumed steps
 *   stepper   (#stepper)  the 23-gate walkthrough              · 24 consumed steps
 *
 * Contract: window.DeckComponents[name] = {mount, onEnter, onLeave, onStep, onStill}.
 * `mount(el)` is called once at load; `onStep(el, k)` returns true when the
 * component CONSUMES the advance (the engine then does not advance builds);
 * `onStill(el)` jumps to the final state (?still screenshots + print).
 *
 * Everything is defensive: a missing circuits payload or a missing mount
 * element must no-op, never throw: a deck that dies at 10:00 in front of a
 * room is worse than a deck with one blank panel.
 *
 * All colour comes from the deck's CSS custom properties (read via
 * getComputedStyle on :root, or via var() inside the injected stylesheet).
 * All geometry is in container-query units against the 16:9 #stage.
 *
 * AGPL-3.0
 */
(function () {
  'use strict';

  /* ------------------------------------------------------------------ *
   * 0. Small utilities
   * ------------------------------------------------------------------ */

  /** prefers-reduced-motion: every animation in here becomes instant. */
  function reducedMotion() {
    try {
      return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    } catch (e) { return false; }
  }

  /** ?still: screenshot/print mode: no transitions, final state only. */
  function stillMode() {
    try {
      if (/[?&]still\b/.test(window.location.search)) return true;
      return document.documentElement.classList.contains('still') ||
             (document.body && document.body.classList.contains('still'));
    } catch (e) { return false; }
  }

  /** Frozen = no animation at all (reduced motion or still). */
  function frozen() { return reducedMotion() || stillMode(); }

  /** Read a deck design token off :root, with a fallback if the CSS is absent. */
  var _tokCache = null;
  function tok(name, fallback) {
    try {
      if (!_tokCache) _tokCache = getComputedStyle(document.documentElement);
      var v = _tokCache.getPropertyValue(name);
      v = v ? v.trim() : '';
      return v || fallback;
    } catch (e) { return fallback; }
  }
  /** Tokens are read lazily but the cache must survive a late stylesheet. */
  function refreshTokens() { _tokCache = null; }

  /** The circuit payload, spliced into frame.html as <script id="circuits">. */
  var _circuits;
  function circuits() {
    if (_circuits !== undefined) return _circuits;
    try {
      var el = document.getElementById('circuits');
      _circuits = el ? JSON.parse(el.textContent) : null;
    } catch (e) { _circuits = null; }
    return _circuits;
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function svgEl(tag, attrs) {
    var n = document.createElementNS('http://www.w3.org/2000/svg', tag);
    if (attrs) for (var k in attrs) if (attrs[k] != null) n.setAttribute(k, String(attrs[k]));
    return n;
  }

  function fmt(n) {
    try { return Number(n).toLocaleString('en-US'); } catch (e) { return String(n); }
  }

  /** Unicode subscript for small integers (wire labels x₁, a₁₀, …). */
  var SUB = ['₀', '₁', '₂', '₃', '₄',
             '₅', '₆', '₇', '₈', '₉'];
  function sub(n) {
    return String(n).split('').map(function (d) { return SUB[+d] || d; }).join('');
  }

  /** Per-element component state, keyed weakly so nothing leaks. */
  function store() {
    var m = new WeakMap();
    return {
      get: function (e) { return e ? m.get(e) : null; },
      set: function (e, v) { if (e) m.set(e, v); return v; }
    };
  }

  /* ------------------------------------------------------------------ *
   * 1. Reversible-gate semantics: the whole simulator, three lines.
   *    (Mirrors src/simulator.jl:1–3 of Bennett.jl; slide s6 shows the
   *    Julia original. Bits are a 1-based boolean array: wires are 1-based
   *    in the JSON, so index 0 is unused.)
   * ------------------------------------------------------------------ */

  function applyGate(b, g) {
    if (!g) return;
    if (g.t === 'NOT') b[g.target] = !b[g.target];
    else if (g.t === 'CNOT') b[g.target] = b[g.target] !== b[g.control];
    else if (g.t === 'TOF') b[g.target] = b[g.target] !== (b[g.c1] && b[g.c2]);
  }

  function freshBits(n) {
    var b = new Array(n + 1);
    for (var i = 0; i <= n; i++) b[i] = false;
    return b;
  }

  /** Decode a wire list LSB-first into an integer. */
  function decode(b, wires) {
    var v = 0;
    for (var i = 0; i < wires.length; i++) if (b[wires[i]]) v |= (1 << i);
    return v;
  }

  function gateName(g) {
    if (!g) return '·';
    if (g.t === 'NOT') return 'NOT w' + g.target;
    if (g.t === 'CNOT') return 'CNOT ' + g.control + '→' + g.target;
    return 'TOF ' + g.c1 + '·' + g.c2 + '→' + g.target;
  }

  /* ------------------------------------------------------------------ *
   * 2. One injected stylesheet for all three components.
   *    Classes are prefixed cb- / en- / st- so nothing collides with the
   *    frame's CSS. Colours are var() references to the deck tokens.
   * ------------------------------------------------------------------ */

  var CSS = [
    /* shared ------------------------------------------------------- */
    '.cb-root,.en-root,.st-root{width:100%;height:100%;display:flex;flex-direction:column;',
    '  color:var(--ink,#E8E6E1);box-sizing:border-box}',
    '.cb-root *,.en-root *,.st-root *{box-sizing:border-box}',
    '.cb-root .mono,.en-root .mono,.st-root .mono{font-family:var(--mono-stack,"JuliaMono",',
    '  ui-monospace,"Cascadia Code","SF Mono",Menlo,Consolas,monospace)}',
    '.cb-root.frozen *,.en-root.frozen *,.st-root.frozen *{transition:none !important;',
    '  animation:none !important}',

    /* 1. costbars -------------------------------------------------- */
    '.cb-root{justify-content:center;gap:2.2cqh;padding:0 1cqw}',
    '.cb-rows{display:flex;flex-direction:column;gap:3.0cqh}',
    '.cb-row{display:grid;grid-template-columns:27cqw 1fr;align-items:center;gap:1.4cqw;',
    '  opacity:0;transition:opacity 320ms ease}',
    '.cb-row.shown{opacity:1}',
    '.cb-label{text-align:right;line-height:1.3}',
    '.cb-ty{color:var(--muted,#8A93A6);font-size:2.1cqh;margin-right:0.7cqw}',
    '.cb-ex{color:var(--ink,#E8E6E1);font-size:2.3cqh}',
    '.cb-track{position:relative;height:5.4cqh}',
    '.cb-plot{position:absolute;inset:0 16cqw 0 0}',
    '.cb-fill{position:absolute;left:0;top:0;bottom:0;width:0;background:var(--blue,#6B8FE8);',
    '  border-radius:0 4px 4px 0;transition:width 600ms cubic-bezier(.22,.61,.36,1)}',
    '.cb-val{position:absolute;top:50%;left:0;transform:translateY(-50%);white-space:nowrap;',
    '  padding-left:1.1cqw;color:var(--ink,#E8E6E1);font-size:2.6cqh;font-weight:600;',
    '  font-variant-numeric:tabular-nums;transition:left 600ms cubic-bezier(.22,.61,.36,1)}',
    '.cb-axis{grid-column:2;position:relative;height:3.2cqh;opacity:0;transition:opacity 320ms ease}',
    '.cb-axis.shown{opacity:1}',
    '.cb-axisplot{position:absolute;inset:0 16cqw 0 0}',
    '.cb-tick{position:absolute;top:0;transform:translateX(-50%);color:var(--muted,#8A93A6);',
    '  font-size:1.9cqh;opacity:0;transition:left 600ms cubic-bezier(.22,.61,.36,1),opacity 400ms ease}',
    '.cb-tick.on{opacity:.45}',
    '.cb-sub{color:var(--muted,#8A93A6);font-size:2.0cqh;opacity:0;transition:opacity 400ms ease;',
    '  padding-top:0.6cqh}',
    '.cb-sub.shown{opacity:1}',

    /* 2. entangle -------------------------------------------------- */
    /* The height budget on s11 is exact: grid + verdict + caption + foot must
     * fit the component box, or the foot rides down onto the "I never wrote a
     * quantum gate" headline that follows it. Root gap and card padding/gap
     * are the three dials, measured, not guessed. */
    '.en-root{justify-content:center;gap:1.0cqh}',
    '.en-grid{display:grid;grid-template-columns:1fr 24cqw 1fr;gap:1.4cqw;align-items:stretch}',
    '.en-card{background:var(--panel,#151A22);border:1px solid var(--line,#232A35);border-radius:10px;',
    '  padding:1.2cqh 1.4cqw;display:flex;flex-direction:column;gap:0.9cqh;opacity:0;',
    '  transform:translateY(1.2cqh);transition:opacity 400ms ease,transform 400ms ease}',
    '.en-root.armed .en-card{opacity:1;transform:none}',
    '.en-cardhead{display:flex;align-items:baseline;justify-content:space-between;gap:1cqw}',
    '.en-name{font-size:2.3cqh;color:var(--muted,#8A93A6);letter-spacing:.02em}',
    '.en-amp{font-size:2.4cqh;color:var(--ink,#E8E6E1);font-variant-numeric:tabular-nums}',
    '.en-chips{display:flex;gap:1.0cqw}',
    '.en-chip{flex:1;display:flex;flex-direction:column;align-items:center;gap:0.5cqh}',
    '.en-chiplab{font-size:1.8cqh;color:var(--muted,#8A93A6)}',
    '.en-val{width:100%;text-align:center;padding:0.8cqh 0;border-radius:8px;font-size:3.0cqh;',
    '  font-weight:700;font-variant-numeric:tabular-nums;border:1px solid var(--line,#232A35);',
    '  background:var(--code-bg,#10151C);color:var(--muted,#8A93A6)}',
    '.en-val.one{color:var(--ink-strong,#FFF);border-color:var(--blue,#6B8FE8)}',
    '.en-chip.flip .en-val{animation:en-pop 240ms cubic-bezier(.3,1.4,.5,1)}',
    '@keyframes en-pop{0%{transform:scale(1)}45%{transform:scale(1.22);',
    '  box-shadow:0 0 0 3px rgba(224,180,95,.28)}100%{transform:scale(1)}}',
    '.en-anc{align-self:flex-start;font-size:1.9cqh;color:var(--muted,#8A93A6);',
    '  border:1px solid var(--line,#232A35);border-radius:999px;padding:0.35cqh 1.0cqw}',
    '.en-anc.flash{animation:en-flash 620ms ease}',
    '@keyframes en-flash{0%{box-shadow:0 0 0 0 rgba(92,189,106,0)}',
    '  40%{box-shadow:0 0 0 3px rgba(92,189,106,.35);color:var(--green,#5CBD6A)}',
    '  100%{box-shadow:0 0 0 0 rgba(92,189,106,0)}}',
    '.en-ket{font-size:2.4cqh;color:var(--ink-strong,#FFF);opacity:0;transition:opacity 400ms ease}',
    '.en-ket.shown{opacity:1}',
    '.en-mid{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0.9cqh;',
    '  text-align:center}',
    '.en-k{font-size:3.4cqh;font-weight:700;color:var(--ink-strong,#FFF);',
    '  font-variant-numeric:tabular-nums}',
    '.en-gate{font-size:2.0cqh;color:var(--blue,#6B8FE8);min-height:2.6cqh}',
    '.en-norm{font-size:1.9cqh;color:var(--muted,#8A93A6);font-variant-numeric:tabular-nums}',
    '.en-verdict{text-align:center;font-size:3.0cqh;color:var(--ink-strong,#FFF);opacity:0;',
    '  transition:opacity 400ms ease;min-height:3.8cqh}',
    '.en-verdict.shown{opacity:1}',
    '.en-verdict em{font-style:normal;color:var(--red,#E06C5F);font-weight:700}',
    '.en-caption{text-align:center;font-size:2.2cqh;color:var(--muted,#8A93A6);min-height:3cqh;',
    '  opacity:0;transition:opacity 320ms ease}',
    '.en-caption.shown{opacity:1}',
    '.en-foot{text-align:center;font-size:1.9cqh;color:var(--muted,#8A93A6);opacity:.85}',

    /* 3. stepper --------------------------------------------------- */
    '.st-root{gap:1.0cqh;align-items:stretch}',
    '.st-svgwrap{flex:1 1 auto;min-height:0;display:flex;align-items:center;justify-content:center}',
    /* height:auto + viewBox keeps the intrinsic 1000:492 ratio even when the
     * parent has no definite height; the cqh cap keeps it clear of the band. */
    '.st-svgwrap svg{width:100%;height:auto;max-height:50cqh;display:block}',
    '.st-bar{display:flex;align-items:center;gap:1.6cqw;flex-wrap:wrap}',
    '.st-stat{font-size:2.1cqh;color:var(--muted,#8A93A6);font-variant-numeric:tabular-nums}',
    '.st-stat b{color:var(--ink,#E8E6E1);font-weight:600}',
    '.st-final{font-size:2.1cqh;color:var(--green,#5CBD6A);opacity:0;transition:opacity 400ms ease}',
    '.st-final.shown{opacity:1}',
    '.st-btn{margin-left:auto;font:inherit;font-size:2.0cqh;color:var(--ink,#E8E6E1);cursor:pointer;',
    '  background:var(--panel,#151A22);border:1px solid var(--line,#232A35);border-radius:8px;',
    '  padding:0.6cqh 1.2cqw;transition:border-color 200ms ease,color 200ms ease}',
    '.st-btn:hover{border-color:var(--gold,#E0B45F);color:var(--ink-strong,#FFF)}',
    '.st-btn.playing{border-color:var(--gold,#E0B45F);color:var(--gold,#E0B45F)}',
    '.st-glow{transition:transform 160ms cubic-bezier(.22,.61,.36,1),opacity 200ms ease}'
  ].join('\n');

  function injectCSS() {
    try {
      if (document.getElementById('deck-components-css')) return;
      var s = document.createElement('style');
      s.id = 'deck-components-css';
      s.textContent = CSS;
      (document.head || document.documentElement).appendChild(s);
    } catch (e) { /* no-op */ }
  }

  /* ================================================================== *
   * COMPONENT 1: costbars
   *
   * A log10 bar chart whose AXIS rescales on every reveal, so the previous
   * champion visibly shrinks as the new bar sweeps in. One measure, one hue
   * (--blue), direct value labels: no legend, no gridlines.
   *
   * Numbers are the verified appendix of DECK-SPEC.md (measured 2026-08-11).
   * ================================================================== */

  var CB = store();

  var CB_ROWS = [
    { ty: 'Int8',    ex: 'x*x + 3x + 1', v: 482,       exp: 3 },
    { ty: 'Float64', ex: 'x + x',        v: 63058,     exp: 5 },
    { ty: 'Float64', ex: 'sin(x)',       v: 11027852,  exp: 8 }
  ];
  var CB_TICKS = [0, 2, 4, 6, 8];
  var CB_SUB = 'measured 2026-08-11 · 1,629,722 NOT · 7,059,276 CNOT · ' +
               '2,338,854 Toffoli · ≤1 ULP vs Base.sin';

  var costbars = {
    mount: function (root) {
      if (!root || CB.get(root)) return;
      injectCSS();
      refreshTokens();
      root.classList.add('cb-root');
      root.textContent = '';

      var rows = el('div', 'cb-rows');
      var st = { root: root, rows: [], ticks: [], shown: 0, exp: CB_ROWS[0].exp };

      CB_ROWS.forEach(function (r) {
        var row = el('div', 'cb-row');
        var lab = el('div', 'cb-label');
        lab.appendChild(el('span', 'cb-ty mono', r.ty));
        lab.appendChild(el('span', 'cb-ex mono', r.ex));
        var track = el('div', 'cb-track');
        var plot = el('div', 'cb-plot');
        var fill = el('div', 'cb-fill');
        // The fill colour is read from the deck token so the chart can never
        // drift from the palette even if this file is reused elsewhere.
        fill.style.background = tok('--blue', '#6B8FE8');
        var val = el('div', 'cb-val', fmt(r.v));
        plot.appendChild(fill);
        plot.appendChild(val);
        track.appendChild(plot);
        row.appendChild(lab);
        row.appendChild(track);
        rows.appendChild(row);
        st.rows.push({ def: r, row: row, fill: fill, val: val });
      });

      var axis = el('div', 'cb-axis');
      var aplot = el('div', 'cb-axisplot');
      CB_TICKS.forEach(function (k) {
        var t = el('div', 'cb-tick mono', '10' + sup(k));
        aplot.appendChild(t);
        st.ticks.push({ k: k, node: t });
      });
      axis.appendChild(aplot);

      // The axis row must line up with the bar plots: it lives in the same
      // grid column as the tracks.
      var grid = el('div', 'cb-row');
      grid.style.opacity = '1';
      grid.appendChild(el('div', ''));
      grid.appendChild(axis);

      var subN = el('div', 'cb-sub', CB_SUB);

      root.appendChild(rows);
      root.appendChild(grid);
      root.appendChild(subN);
      st.axis = axis;
      st.sub = subN;

      CB.set(root, st);
      if (frozen()) root.classList.add('frozen');
      cbApply(st);
      if (stillMode()) costbars.onStill(root);
    },

    onEnter: function (root) {
      var st = CB.get(root);
      if (!st) return;
      root.classList.toggle('frozen', frozen());
      if (stillMode()) { costbars.onStill(root); return; }
      cbReset(st);
    },

    onLeave: function (root) {
      var st = CB.get(root);
      if (!st || stillMode()) return;
      cbReset(st);
    },

    /* Consumes exactly three advances (one per bar); the honesty footer that
     * follows is an ordinary .build owned by the slide, so the fourth advance
     * must fall through to the engine. */
    onStep: function (root) {
      var st = CB.get(root);
      if (!st) return false;
      if (st.shown >= CB_ROWS.length) return false;
      st.shown += 1;
      cbReveal(st);
      return true;
    },

    onStill: function (root) {
      var st = CB.get(root);
      if (!st) return;
      root.classList.add('frozen');
      st.shown = CB_ROWS.length;
      cbReveal(st);
    }
  };

  function sup(k) {
    var S = { 0: '⁰', 2: '²', 4: '⁴', 6: '⁶', 8: '⁸' };
    return S[k] != null ? S[k] : String(k);
  }

  function cbReset(st) {
    st.shown = 0;
    st.exp = CB_ROWS[0].exp;
    st.rows.forEach(function (r) { r.row.classList.remove('shown'); });
    st.axis.classList.remove('shown');
    st.sub.classList.remove('shown');
    cbApply(st);
  }

  function cbReveal(st) {
    // The axis exponent is that of the largest revealed bar; this is the
    // rescale that makes the earlier bars shrink.
    st.exp = CB_ROWS[Math.max(0, st.shown - 1)].exp;
    st.rows.forEach(function (r, i) { r.row.classList.toggle('shown', i < st.shown); });
    st.axis.classList.toggle('shown', st.shown > 0);
    st.sub.classList.toggle('shown', st.shown >= 3);
    if (frozen()) cbApply(st);
    else requestAnimationFrame(function () { cbApply(st); });
  }

  function cbApply(st) {
    var exp = st.exp || 1;
    st.rows.forEach(function (r, i) {
      var f = (i < st.shown) ? clamp01(Math.log10(r.def.v) / exp) : 0;
      r.fill.style.width = (f * 100).toFixed(3) + '%';
      r.val.style.left = (f * 100).toFixed(3) + '%';
    });
    st.ticks.forEach(function (t) {
      var on = t.k <= exp + 1e-9;
      t.node.classList.toggle('on', on && st.shown > 0);
      t.node.style.left = (clamp01(t.k / exp) * 100).toFixed(3) + '%';
    });
  }

  function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

  /* ================================================================== *
   * COMPONENT 2: entangle
   *
   * The deck runs the actual compiled circuit. `controlled(·)` turns a
   * reversible circuit into a permutation controlled on wire 50; a state
   *
   *     (|ctrl=0> + |ctrl=1>)/sqrt(2)  (x) |x=0, anc=0>
   *
   * is therefore ALWAYS exactly two computational branches with amplitude
   * 1/sqrt(2) each: permutations map basis states to basis states, so no
   * amplitude ever splits. That is why two 50-bit arrays are a *complete*
   * statevector simulation here, not an approximation.
   *
   * Seven consumed advances: prepare, 4x(5 gates), ket reveal, verdict.
   * ================================================================== */

  var EN = store();
  var EN_TOTAL_STEPS = 7;
  var EN_CHUNK = 5;

  var entangle = {
    mount: function (root) {
      if (!root || EN.get(root)) return;
      injectCSS();
      refreshTokens();
      root.classList.add('en-root');
      root.textContent = '';

      var c = circuits() && circuits().controlled_not;
      if (!c || !c.gates) {                       // no data → visible but inert
        root.appendChild(el('div', 'en-foot', 'circuit data unavailable'));
        return;
      }

      var ctrlW = c.control_wire || 50;
      var xW = (c.input_wires && c.input_wires[1]) || 1;
      var outW = (c.output_wires && c.output_wires[0]) || 42;
      var anc = c.ancilla_wires || [];

      var st = {
        root: root, c: c, ctrlW: ctrlW, xW: xW, outW: outW, anc: anc,
        step: 0, k: 0, cards: []
      };

      var grid = el('div', 'en-grid');
      st.cards.push(enCard(st, 'branch A', false));
      var mid = el('div', 'en-mid');
      st.kNode = el('div', 'en-k mono', '0/' + c.gates.length);
      st.gNode = el('div', 'en-gate mono', '');
      // The norm is genuinely computed from the two amplitudes, not printed.
      var amp = Math.SQRT1_2;
      st.normNode = el('div', 'en-norm mono',
        '‖ψ‖ = ' + Math.sqrt(amp * amp + amp * amp).toFixed(10));
      mid.appendChild(st.kNode);
      mid.appendChild(st.gNode);
      mid.appendChild(st.normNode);
      st.cards.push(enCard(st, 'branch B', true));

      grid.appendChild(st.cards[0].node);
      grid.appendChild(mid);
      grid.appendChild(st.cards[1].node);

      st.verdict = el('div', 'en-verdict');
      st.caption = el('div', 'en-caption');
      var foot = el('div', 'en-foot',
        'the deck is running the compiled circuit: ' + c.gates.length +
        ' gates on both branches, live in your browser');

      root.appendChild(grid);
      root.appendChild(st.verdict);
      root.appendChild(st.caption);
      root.appendChild(foot);

      EN.set(root, st);
      if (frozen()) root.classList.add('frozen');
      enReset(st);
      if (stillMode()) entangle.onStill(root);
    },

    onEnter: function (root) {
      var st = EN.get(root);
      if (!st) return;
      root.classList.toggle('frozen', frozen());
      if (stillMode()) { entangle.onStill(root); return; }
      enReset(st);
    },

    onLeave: function (root) {
      var st = EN.get(root);
      if (!st || stillMode()) return;
      enReset(st);
    },

    onStep: function (root) {
      var st = EN.get(root);
      if (!st) return false;
      if (st.step >= EN_TOTAL_STEPS) return false;
      st.step += 1;
      enRender(st, false);
      return true;
    },

    onStill: function (root) {
      var st = EN.get(root);
      if (!st) return;
      root.classList.add('frozen');
      st.step = EN_TOTAL_STEPS;
      enRender(st, true);
    }
  };

  function enCard(st, name, isB) {
    var node = el('div', 'en-card');
    var head = el('div', 'en-cardhead');
    head.appendChild(el('div', 'en-name', name));
    head.appendChild(el('div', 'en-amp mono', '1/√2'));
    var chips = el('div', 'en-chips');
    var mk = function (label) {
      var chip = el('div', 'en-chip');
      chip.appendChild(el('div', 'en-chiplab mono', label));
      var v = el('div', 'en-val mono', '0');
      chip.appendChild(v);
      chips.appendChild(chip);
      return { chip: chip, val: v };
    };
    var ctrl = mk('ctrl · w' + st.ctrlW);
    var x = mk('x · w' + st.xW);
    var out = mk('out · w' + st.outW);
    var ancPill = el('div', 'en-anc mono', 'ancillae Σ=0');
    var ket = el('div', 'en-ket mono', '');
    node.appendChild(head);
    node.appendChild(chips);
    node.appendChild(ancPill);
    node.appendChild(ket);
    return { node: node, isB: isB, ctrl: ctrl, x: x, out: out, anc: ancPill, ket: ket, bits: null };
  }

  function enReset(st) {
    st.step = 0;
    st.k = 0;
    st.root.classList.remove('armed');
    st.verdict.classList.remove('shown');
    st.caption.classList.remove('shown');
    st.caption.textContent = '';
    st.cards.forEach(function (card) {
      card.bits = freshBits(st.c.n_wires || 50);
      card.ket.classList.remove('shown');
      card.ket.textContent = '';
    });
    st.kNode.textContent = '0/' + st.c.gates.length;
    st.gNode.textContent = '';
    enPaint(st, false);
  }

  /**
   * Render the component at st.step.
   *  step 0        nothing (cards hidden)
   *  step 1        prepare: cards in, branch B ctrl = 1
   *  steps 2..5    run gates in chunks of 5  → k = 5, 10, 15, 20
   *  step 6        ket reveal + ancilla pills flash
   *  step 7        verdict line
   * The simulation is recomputed from scratch for the target k so that
   * jumping (onStill) and stepping give bit-identical state.
   */
  function enRender(st, instant) {
    var gates = st.c.gates;
    var targetK = 0;
    if (st.step >= 2) targetK = Math.min(gates.length, (st.step - 1) * EN_CHUNK);
    if (st.step >= 6) targetK = gates.length;

    st.root.classList.toggle('armed', st.step >= 1);

    // Recompute both branches from the prepared state up to targetK.
    var prev = st.cards.map(function (card) { return card.bits; });
    st.cards.forEach(function (card) {
      var b = freshBits(st.c.n_wires || 50);
      if (card.isB && st.step >= 1) b[st.ctrlW] = true;   // |ctrl=1> branch
      for (var i = 0; i < targetK; i++) applyGate(b, gates[i]);
      card.bits = b;
    });
    st.k = targetK;

    st.kNode.textContent = targetK + '/' + gates.length;
    st.gNode.textContent = targetK > 0 ? gateName(gates[targetK - 1]) : '';

    var animate = !instant && !frozen() && st.step >= 1;
    enPaint(st, animate, prev);

    if (st.step === 1) {
      enCaption(st, 'H on the control: a superposition of two classical worlds');
    } else if (st.step >= 2 && st.step <= 5) {
      enCaption(st, 'gates ' + Math.max(1, targetK - EN_CHUNK + 1) + '–' + targetK +
                    ' applied to both branches: permutations, so no amplitude moves');
    } else if (st.step === 6) {
      enCaption(st, 'every ancilla is back to zero: the branches differ only in ctrl and out');
    } else if (st.step >= 7) {
      enCaption(st, 'one control wire, twenty compiled gates, no hand-written quantum gate');
    }

    // Kets + ancilla flash on step 6.
    st.cards.forEach(function (card) {
      if (st.step >= 6) {
        var b = card.bits;
        card.ket.textContent = '|ctrl,x,out⟩ = |' +
          bit(b[st.ctrlW]) + ',' + bit(b[st.xW]) + ',' + bit(b[st.outW]) + '⟩';
        card.ket.classList.add('shown');
        if (!instant && !frozen()) flash(card.anc, 'flash', 640);
      } else {
        card.ket.classList.remove('shown');
        card.ket.textContent = '';
      }
    });

    if (st.step >= 7) {
      st.verdict.textContent = '';
      var kets = st.cards.map(function (card) {
        var b = card.bits;
        return '|' + bit(b[st.ctrlW]) + ',' + bit(b[st.xW]) + ',' + bit(b[st.outW]) + '⟩';
      });
      st.verdict.appendChild(document.createTextNode(
        '(' + kets[0] + ' + ' + kets[1] + ')/√2 · '));
      st.verdict.appendChild(el('em', '', 'entangled'));
      st.verdict.classList.add('shown');
    } else {
      st.verdict.classList.remove('shown');
      st.verdict.textContent = '';
    }
  }

  function bit(b) { return b ? '1' : '0'; }

  function enCaption(st, text) {
    st.caption.textContent = text;
    st.caption.classList.add('shown');
  }

  function enPaint(st, animate, prev) {
    st.cards.forEach(function (card, i) {
      var b = card.bits;
      var old = prev && prev[i];
      enChip(card.ctrl, b[st.ctrlW], old ? old[st.ctrlW] : null, animate);
      enChip(card.x, b[st.xW], old ? old[st.xW] : null, animate);
      enChip(card.out, b[st.outW], old ? old[st.outW] : null, animate);
      var s = 0;
      for (var j = 0; j < st.anc.length; j++) if (b[st.anc[j]]) s++;
      card.anc.textContent = 'ancillae Σ=' + s;
    });
  }

  function enChip(chip, value, wasValue, animate) {
    var txt = bit(value);
    var changed = (wasValue != null) && (!!value !== !!wasValue);
    chip.val.textContent = txt;
    chip.val.classList.toggle('one', !!value);
    if (animate && changed) flash(chip.chip, 'flip', 260);
  }

  /** Add a class, strip it after ms: the "fast flip" without CSS bookkeeping. */
  function flash(node, cls, ms) {
    try {
      node.classList.remove(cls);
      void node.offsetWidth;                       // restart the animation
      node.classList.add(cls);
      setTimeout(function () { node.classList.remove(cls); }, ms);
    } catch (e) { /* no-op */ }
  }

  /* ================================================================== *
   * COMPONENT 3: stepper
   *
   * The 23-gate x+1 circuit, one gate per advance, on a JS-generated SVG.
   * Verified against circuits.json: with x = 3 preset LSB-first on wires
   * [1,2,3], executing all 23 gates leaves the output wires [14,15,16]
   * holding 0,0,1 → decoded LSB-first that is 4, and every ancilla is back
   * to zero. gs[14:23] == reverse(gs[1:10]): Bennett's theorem, on screen.
   * ================================================================== */

  var ST = store();
  var ST_X = 3;                 // input preset
  var ST_RATE = 1000 / 6;       // "run all" autoplay: 6 gates/s

  // Phase partition of the 23 gates (1-based inclusive), per the spec.
  var ST_PHASES = [
    { from: 1,  to: 10, label: 'compute',   color: '--blue' },
    { from: 11, to: 13, label: 'copy',      color: '--green' },
    { from: 14, to: 23, label: 'uncompute', color: '--purple' }
  ];

  var stepper = {
    mount: function (root) {
      if (!root || ST.get(root)) return;
      injectCSS();
      refreshTokens();
      root.classList.add('st-root');
      root.textContent = '';

      var c = circuits() && circuits().x_plus_1;
      if (!c || !c.gates) {
        root.appendChild(el('div', 'st-stat', 'circuit data unavailable'));
        return;
      }

      var st = { root: root, c: c, k: 0, done: false, timer: null };
      st.wrap = el('div', 'st-svgwrap');
      root.appendChild(st.wrap);

      var bar = el('div', 'st-bar');
      st.stat = el('div', 'st-stat mono');
      st.final = el('div', 'st-final mono',
        'out = 4  ·  every ancilla back to 0  ·  gs[14:23] == reverse(gs[1:10])');
      st.btn = el('button', 'st-btn', '⟲ run all');
      st.btn.type = 'button';
      st.btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();                      // never trigger deck click-nav
        stToggleRun(st);
      });
      bar.appendChild(st.stat);
      bar.appendChild(st.final);
      bar.appendChild(st.btn);
      root.appendChild(bar);

      stBuildSVG(st);
      ST.set(root, st);
      if (frozen()) root.classList.add('frozen');
      stSet(st, 0, false);
      if (stillMode()) stepper.onStill(root);
    },

    onEnter: function (root) {
      var st = ST.get(root);
      if (!st) return;
      root.classList.toggle('frozen', frozen());
      if (stillMode()) { stepper.onStill(root); return; }
      stStop(st);
      stSet(st, 0, false);
    },

    onLeave: function (root) {
      var st = ST.get(root);
      if (!st) return;
      stStop(st);
      if (!stillMode()) stSet(st, 0, false);
    },

    /* One gate per advance (23), then one final consumed step for the
     * verdict line; after that the advance falls through to the engine. */
    onStep: function (root) {
      var st = ST.get(root);
      if (!st) return false;
      stStop(st);
      if (st.k < st.c.gates.length) { stSet(st, st.k + 1, false); return true; }
      if (!st.done) { stSet(st, st.k, true); return true; }
      return false;
    },

    onStill: function (root) {
      var st = ST.get(root);
      if (!st) return;
      root.classList.add('frozen');
      stStop(st);
      stSet(st, st.c.gates.length, true);
    }
  };

  /* --- geometry (user units; the viewBox scales with the container) --- */
  var SV = { W: 1000, H: 492, padL: 84, padR: 74, top: 62, rowH: 26 };

  function wireY(i) { return SV.top + i * SV.rowH; }                 // i = 0-based
  function wY(w) { return wireY(w - 1); }
  function colX(j, n) {                                             // j = 0-based gate
    var w = (SV.W - SV.padL - SV.padR) / n;
    return SV.padL + w * (j + 0.5);
  }
  function colW(n) { return (SV.W - SV.padL - SV.padR) / n; }

  function stBuildSVG(st) {
    var c = st.c, n = c.gates.length, nw = c.n_wires;
    var T = {
      line: tok('--line', '#232A35'),
      muted: tok('--muted', '#8A93A6'),
      ink: tok('--ink', '#E8E6E1'),
      inkS: tok('--ink-strong', '#FFFFFF'),
      bg: tok('--bg', '#0E1116'),
      codebg: tok('--code-bg', '#10151C'),
      green: tok('--green', '#5CBD6A'),
      blue: tok('--blue', '#6B8FE8'),
      purple: tok('--purple', '#B385D6'),
      gold: tok('--gold', '#E0B45F')
    };
    st.T = T;

    var svg = svgEl('svg', {
      viewBox: '0 0 ' + SV.W + ' ' + SV.H,
      preserveAspectRatio: 'xMidYMid meet',
      role: 'img',
      'aria-label': '23-gate reversible increment circuit'
    });

    // --- phase bands (behind everything) ---------------------------
    var bands = svgEl('g');
    ST_PHASES.forEach(function (p) {
      var x0 = colX(p.from - 1, n) - colW(n) / 2;
      var x1 = colX(p.to - 1, n) + colW(n) / 2;
      var col = tok(p.color, '#6B8FE8');
      bands.appendChild(svgEl('rect', {
        x: x0, y: SV.top - 22, width: x1 - x0, height: (nw - 1) * SV.rowH + 44,
        rx: 8, fill: col, opacity: 0.07
      }));
      var lab = svgEl('text', {
        x: (x0 + x1) / 2, y: SV.top - 32, 'text-anchor': 'middle',
        fill: col, opacity: 0.75, 'font-size': 15, 'letter-spacing': '0.06em'
      });
      lab.textContent = p.label;
      bands.appendChild(lab);
    });
    svg.appendChild(bands);

    // --- current-column gold underglow (a translated group so the move
    //     animates through a CSS transform transition) ------------------
    var glow = svgEl('g', { class: 'st-glow', opacity: 0 });
    glow.appendChild(svgEl('rect', {
      x: -colW(n) / 2, y: SV.top - 18, width: colW(n), height: (nw - 1) * SV.rowH + 36,
      rx: 7, fill: T.gold, opacity: 0.16
    }));
    glow.appendChild(svgEl('rect', {
      x: -1, y: SV.top - 18, width: 2, height: (nw - 1) * SV.rowH + 36,
      fill: T.gold, opacity: 0.5
    }));
    svg.appendChild(glow);
    st.glow = glow;

    // --- wires + labels --------------------------------------------
    var wires = svgEl('g');
    st.dots = [];
    for (var w = 1; w <= nw; w++) {
      var y = wY(w);
      wires.appendChild(svgEl('line', {
        x1: SV.padL - 26, y1: y, x2: SV.W - SV.padR + 4, y2: y,
        stroke: T.line, 'stroke-width': 1.2
      }));
      var t = svgEl('text', {
        x: SV.padL - 34, y: y + 4.5, 'text-anchor': 'end',
        fill: T.muted, 'font-size': 14
      });
      t.textContent = stWireLabel(c, w);
      wires.appendChild(t);

      // right-edge bit dot (filled = 1, hollow = 0)
      var d = svgEl('circle', {
        cx: SV.W - SV.padR + 22, cy: y, r: 5.2,
        fill: 'none', stroke: T.muted, 'stroke-width': 1.4
      });
      wires.appendChild(d);
      st.dots.push(d);
    }
    svg.appendChild(wires);

    // --- gates ------------------------------------------------------
    var gatesG = svgEl('g');
    st.gateNodes = [];
    c.gates.forEach(function (g, j) {
      var x = colX(j, n);
      var col = g.t === 'NOT' ? T.green : (g.t === 'CNOT' ? T.blue : T.purple);
      var grp = svgEl('g', { opacity: 0.35 });
      var ys = [wY(g.target)];
      if (g.t === 'CNOT') ys.push(wY(g.control));
      if (g.t === 'TOF') { ys.push(wY(g.c1)); ys.push(wY(g.c2)); }
      if (ys.length > 1) {
        grp.appendChild(svgEl('line', {
          x1: x, y1: Math.min.apply(null, ys), x2: x, y2: Math.max.apply(null, ys),
          stroke: col, 'stroke-width': 1.6
        }));
      }
      // control dots
      if (g.t === 'CNOT') grp.appendChild(svgEl('circle', { cx: x, cy: wY(g.control), r: 4, fill: col }));
      if (g.t === 'TOF') {
        grp.appendChild(svgEl('circle', { cx: x, cy: wY(g.c1), r: 4, fill: col }));
        grp.appendChild(svgEl('circle', { cx: x, cy: wY(g.c2), r: 4, fill: col }));
      }
      // the ⊕ target ring
      var ty = wY(g.target), r = 7.6;
      grp.appendChild(svgEl('circle', {
        cx: x, cy: ty, r: r, fill: T.bg, stroke: col, 'stroke-width': 1.8
      }));
      grp.appendChild(svgEl('line', { x1: x - r, y1: ty, x2: x + r, y2: ty, stroke: col, 'stroke-width': 1.6 }));
      grp.appendChild(svgEl('line', { x1: x, y1: ty - r, x2: x, y2: ty + r, stroke: col, 'stroke-width': 1.6 }));
      gatesG.appendChild(grp);
      st.gateNodes.push(grp);
    });
    svg.appendChild(gatesG);

    st.wrap.appendChild(svg);
    st.svg = svg;
  }

  function stWireLabel(c, w) {
    var i = c.input_wires.indexOf(w);
    if (i >= 0) return 'x' + sub(i + 1);
    var o = c.output_wires.indexOf(w);
    if (o >= 0) return 'out' + sub(o + 1);
    return 'a' + sub(w);
  }

  /**
   * Set the circuit to "k gates executed", optionally showing the verdict.
   * The bit state is recomputed from the x = 3 preset every time, so a jump
   * (onStill, run-all) and a walk give identical state, no incremental drift.
   */
  function stSet(st, k, done) {
    var c = st.c, n = c.gates.length;
    st.k = Math.max(0, Math.min(n, k));
    st.done = !!done;

    var b = freshBits(c.n_wires);
    c.input_wires.forEach(function (w, i) { b[w] = !!((ST_X >> i) & 1); });   // LSB-first
    for (var i = 0; i < st.k; i++) applyGate(b, c.gates[i]);

    // executed gates go full opacity; the rest stay ghosted
    st.gateNodes.forEach(function (g, j) { g.setAttribute('opacity', j < st.k ? '1' : '0.3'); });

    // gold underglow follows the current column (the gate just executed;
    // before the first advance it sits on the gate about to run)
    var j = st.k > 0 ? st.k - 1 : 0;
    st.glow.setAttribute('opacity', st.k > 0 ? '1' : '0.45');
    st.glow.style.transform = 'translateX(' + colX(j, n).toFixed(2) + 'px)';

    // right-edge bit dots
    for (var w = 1; w <= c.n_wires; w++) {
      var d = st.dots[w - 1];
      if (!d) continue;
      if (b[w]) { d.setAttribute('fill', st.T.inkS); d.setAttribute('stroke', st.T.inkS); }
      else { d.setAttribute('fill', 'none'); d.setAttribute('stroke', st.T.muted); }
    }

    var out = decode(b, c.output_wires);
    var anc = c.ancilla_wires.reduce(function (s, w2) { return s + (b[w2] ? 1 : 0); }, 0);
    var outBits = c.output_wires.map(function (w2) { return b[w2] ? '1' : '0'; }).join('');

    st.stat.textContent = '';
    st.stat.appendChild(el('b', '', 'gate ' + st.k + '/' + n));
    st.stat.appendChild(document.createTextNode(
      '  ·  ' + (st.k > 0 ? gateName(c.gates[st.k - 1]) : 'x = ' + ST_X + ' preset') +
      '  ·  out = ' + out + ' (' + outBits + ' LSB-first)' +
      '  ·  ancillae Σ=' + anc));
    st.final.classList.toggle('shown', st.done);
    if (st.done) {
      // Recomputed, not pinned: the verdict states what the simulation found.
      var pal = JSON.stringify(c.gates.slice(13, 23)) ===
                JSON.stringify(c.gates.slice(0, 10).slice().reverse());
      st.final.textContent = 'out = ' + out + '  ·  ' +
        (anc === 0 ? 'every ancilla back to 0' : 'ancillae Σ=' + anc + ' (!)') +
        '  ·  gs[14:23] == reverse(gs[1:10])' + (pal ? '' : ', FALSE (!)');
    }
  }

  function stToggleRun(st) {
    if (st.timer) { stStop(st); return; }
    stSet(st, 0, false);
    st.btn.classList.add('playing');
    st.btn.textContent = '■ stop';
    st.timer = setInterval(function () {
      if (st.k < st.c.gates.length) stSet(st, st.k + 1, false);
      else { stSet(st, st.k, true); stStop(st); }
    }, frozen() ? 1 : ST_RATE);
  }

  function stStop(st) {
    if (st.timer) { clearInterval(st.timer); st.timer = null; }
    if (st.btn) { st.btn.classList.remove('playing'); st.btn.textContent = '⟲ run all'; }
  }

  /* ================================================================== *
   * Registry: every entry point is wrapped so a component fault can
   * never take the deck down mid-talk.
   * ================================================================== */

  function guard(name, obj) {
    var out = {};
    ['mount', 'onEnter', 'onLeave', 'onStep', 'onStill'].forEach(function (m) {
      out[m] = function (a, b) {
        try { return obj[m] ? obj[m](a, b) : (m === 'onStep' ? false : undefined); }
        catch (e) {
          try { console.warn('[DeckComponents:' + name + '.' + m + ']', e); } catch (_) {}
          return m === 'onStep' ? false : undefined;
        }
      };
    });
    return out;
  }

  window.DeckComponents = {
    costbars: guard('costbars', costbars),
    entangle: guard('entangle', entangle),
    stepper: guard('stepper', stepper)
  };
})();
