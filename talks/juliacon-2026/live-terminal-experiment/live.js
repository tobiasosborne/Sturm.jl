/* Live terminal mirror (EXPERIMENT) — injected into talk-live.html by
 * make_live.py. Mirrors the tmux pane streamed by bridge.py into the deck's
 * terminal band (#band-out), reusing the deck's own .term-line/.term-prompt
 * styling so the mirror looks native.
 *
 * Behavior contract:
 *  - Mirrors ONLY while the current slide's band is in the "live" state
 *    (slides declare data-band="live"), unless the URL carries ?livealways,
 *    which mirrors on every slide (for testing).
 *  - The engine repaints the band on slide changes; a 250 ms repaint loop
 *    wins it back while the stream is connected. Disconnected -> the loop
 *    stops touching the DOM entirely, so the deck degrades to its scripted
 *    shadow behavior (the pre-experiment status quo).
 *  - Read-only: no keystrokes are captured or forwarded. You type in the
 *    real terminal; the deck watches.
 */
(function () {
  'use strict';
  var BRIDGE = 'http://127.0.0.1:8123/stream';
  var ALWAYS = /[?&]livealways\b/.test(location.href);
  var connected = false;
  var lines = [];
  var weOwnBand = false;

  var band = document.getElementById('band');
  var bandOut = document.getElementById('band-out');
  var bandState = document.getElementById('band-state');
  if (!band || !bandOut) return;

  function shouldMirror() {
    return connected && (ALWAYS || band.getAttribute('data-state') === 'live');
  }

  function render() {
    if (!shouldMirror()) {
      // If we painted the band and the slide moved off "live", let go once;
      // the engine's own nav repaint restores scripted content.
      weOwnBand = false;
      return;
    }
    bandOut.textContent = '';
    lines.forEach(function (text) {
      var m = text.match(/^(\s*(?:julia>|\$|shell>|help\?>)\s?)([\s\S]*)$/);
      var line = document.createElement('div');
      line.className = 'term-line';
      var hs = document.createElement('span');
      hs.className = 'term-prompt';
      hs.textContent = m ? m[1] : '';
      var ts = document.createElement('span');
      ts.className = 'term-text';
      ts.textContent = m ? m[2] : text;
      line.appendChild(hs);
      line.appendChild(ts);
      bandOut.appendChild(line);
    });
    if (bandState) bandState.textContent = '● LIVE · mirror';
    weOwnBand = true;
  }

  function connect() {
    var es = new EventSource(BRIDGE);
    es.onopen = function () { connected = true; };
    es.onmessage = function (ev) {
      try { lines = JSON.parse(ev.data).lines || []; } catch (e) { return; }
      render();
    };
    es.onerror = function () {
      // EventSource auto-reconnects; until then, stop owning the band.
      connected = false;
      if (weOwnBand) {
        weOwnBand = false;
        if (bandState && band.getAttribute('data-state') === 'live') {
          bandState.textContent = '● LIVE';
        }
      }
    };
  }

  connect();
  // Repaint loop: survives the engine's own band writes on slide nav.
  window.setInterval(render, 250);
})();
