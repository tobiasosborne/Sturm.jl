# Live terminal mirror — EXPERIMENT

The deck's bottom band, fed by your **real terminal** instead of scripted
shadow text. The main talk (`../talk.html`) is untouched; this folder is a
self-contained experiment.

## How it works

```
you type here                      audience sees this
┌──────────────┐   tmux    ┌───────────┐   SSE (localhost)   ┌────────────────┐
│ real terminal │ ────────▶ │ bridge.py │ ──────────────────▶ │ deck band      │
│ (tmux session)│  capture  │ (stdlib)  │   10 Hz, on-change  │ #band-out      │
└──────────────┘           └───────────┘                     └────────────────┘
```

Read-only by design: no keystrokes go from browser to shell. The deck
*mirrors* the tmux pane, so the presenter workflow from the runbook
(type in the real terminal) is unchanged — the projector just shows it
inside the slide.

## Run it

```bash
tmux new-session -s sturmdemo          # terminal 1: the demo terminal
python3 bridge.py                      # terminal 2: the mirror bridge
# then open http://127.0.0.1:8123/    # the deck, same-origin, zero CORS fuss
```

`make_live.py` builds `talk-live.html` from `../talk.html` + `live.js`.
**Rerun it after any rebuild of the main deck** — `talk-live.html` is a
generated copy, not a fork.

## Two-screen setup (projector + laptop display)

- Projector: browser fullscreen on `http://127.0.0.1:8123/` (the deck).
- Laptop display: the `sturmdemo` tmux terminal, where you actually type.
- The band mirrors with ~100–300 ms latency (10 Hz poll). Keep the tmux
  window at a sane width (~100 cols) so lines don't wrap oddly in the band.

## Behavior contract

- The mirror paints ONLY on slides marked `data-band="live"` (4 in the
  current deck). Everywhere else the band behaves exactly as stock.
- `?livealways` in the URL mirrors on every slide — handy for testing.
- If the bridge dies or was never started, the deck silently reverts to
  its scripted shadow behavior. Verified: the failure mode on stage is
  "the talk before this experiment existed".
- `?still` / PDF export are unaffected (the mirror never paints in still
  mode because it only overwrites on live SSE data; the print pipeline
  uses `../talk.html` anyway).

## Current limitations (deliberate, it's an experiment)

- Plain text only: ANSI colors are stripped by `tmux capture-pane` without
  `-e`. The band's own `julia>` prompt highlighting is applied instead.
- Tail of 12 lines (`--lines`); the band fits ~7, oldest clip off the top
  like a real terminal.
- The bridge binds 127.0.0.1 only — nothing is exposed to the network.
