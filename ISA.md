---
phase: complete
progress: 14/14
task: "Fix latex toolchain probe and add offline KaTeX math"
slug: org-ppt
iteration: 2
started: 2026-09-01T00:00:00Z
updated: 2026-09-01T00:00:00Z
principal_stated_goal: "yes, fix the probe and add offline KaTeX"
principal_stated_goal_source: prompt
principal_stated_goal_signal: 1
principal_stated_goal_locked: 2026-09-01T00:00:00Z
---

# org-ppt — math without a TeX installation

## Problem

`org-ppt--resolved-latex` decides whether math can be rendered by probing a single
binary, `latex`. The `dvipng` process it defaults to also needs `dvipng`, and the
`imagemagick` process needs `convert`. On a machine carrying TeX but not the
companion tool, the downgrade never fires and a deck containing math fails mid
export instead of degrading. Separately, the only way to get typeset math into a
deck today is to install a TeX distribution — a heavy dependency for the one
feature that needs it, and the reason the question was asked at all.

## Vision

Math in a deck just works on a machine that has never heard of TeX, and the
exported file is still one self-contained HTML that opens from a USB stick with
the network unplugged. Nobody installs anything; nobody notices there was ever a
dependency.

## Out of Scope

Rendering math to images without TeX, MathML output modes, editing the Org math
syntax, replacing the `dvipng` path for people who prefer image math, and
lazy-loading KaTeX from a CDN.

## Principles

- A missing tool produces a named message, never a silent visual downgrade.
- A capability probe asks the toolchain what it needs; it does not hardcode a guess.
- Self-containment is the product. Anything the deck needs at display time travels inside the file.

## Constraints

- The exported HTML must reference no network resource of any kind.
- A deck with no math must not carry any KaTeX payload.
- Existing `dvipng` / `imagemagick` / `verbatim` behaviour stays available and unchanged.
- Vendored third-party assets keep their upstream licence file.

## Goal

`org-ppt-with-latex` defaults to a new `katex` mode that typesets math client-side
from KaTeX assets inlined into the exported file, so no TeX installation is
required; and the availability probe for the image-rendering modes checks every
program the selected Org preview process declares, downgrading with a message that
names what is missing.

## Claims

- [x] ISC-1: `org-ppt--resolved-latex` checks every entry in the selected process's
      `:programs` list from `org-preview-latex-process-alist`, not just `latex`.
- [x] ISC-2: When a required program is missing, export downgrades to the configured
      fallback and emits one message naming the missing program.
- [x] ISC-3: In `katex` mode the exported HTML contains typeset math rendered by
      KaTeX in a real browser, on a machine with no TeX installed.
- [x] ISC-4: The exported HTML references no external URL — no CDN script, no
      stylesheet link, no remaining `url(fonts/…)` in the inlined KaTeX CSS.
- [x] ISC-5: A deck containing no math carries no KaTeX payload, measured as export
      size parity with the pre-change exporter.
- [x] ISC-6: `org-ppt-with-latex` defaults to `katex`, so a fresh install renders
      math with no configuration and no system dependency.
- [x] ISC-7: Existing behaviour is preserved — the full ERT suite passes and the
      demo deck still exports to its previous slide count.
- [x] ISC-8: Anti: no network request is issued when the exported deck is opened,
      and no `http`-scheme reference survives in the output for any deck.

- [x] ISC-9: With Node on PATH the deck is typeset at export time and ships no
      KaTeX runtime — finished HTML and a stylesheet, nothing to execute.
- [x] ISC-10: Only the font families the rendered math reaches for are inlined.
- [x] ISC-11: Both paths render the same page, so the size saving costs no fidelity.
- [x] ISC-12: Without Node the deck falls back to the runtime and every face, and
      still renders offline — a smaller file is never traded for a broken one.
- [x] ISC-13: Anti: no replacement function corrupts the match data its caller
      splices on; every such lambda in the file, not only the new one.
- [x] ISC-14: A deck with no math is unchanged from the pre-KaTeX exporter.

## Test Strategy

| isc | type | check | threshold | tool | anchors_to |
|-----|------|-------|-----------|------|------------|
| ISC-1 | unit | ERT asserts the probe reads `:programs` and rejects a partial toolchain | pass | `make test` | literal |
| ISC-2 | unit | ERT captures the downgrade message and asserts it names the absent binary | message names binary | `make test` | derived: named degradation |
| ISC-3 | visual | Chromium renders the demo deck; math slide screenshot shows typeset output | KaTeX DOM present, glyphs visible | headless Chromium screenshot | literal |
| ISC-4 | grep | scan exported HTML for `http`, `<link`, `url(fonts/` | zero matches | `grep` | literal |
| ISC-5 | size | export math-free deck before/after change, compare bytes | delta < 2 KB | `stat` | derived: no cost when unused |
| ISC-6 | unit | ERT asserts the defcustom default value | `katex` | `make test` | literal |
| ISC-7 | regression | full ERT suite plus demo export slide count | all pass, count unchanged | `make test`, `grep -c` | derived: no regression |
| ISC-8 | runtime | Chromium console and network log while loading the deck offline | zero requests, zero errors | headless Chromium | literal |
| ISC-9 | export | grep exported deck for the runtime call and for typeset spans | 0 runtime, >0 `class="katex` | `grep` | literal |
| ISC-10 | export | count `@font-face` blocks in a deck using ordinary symbols | 6 of 20 | `grep` | literal |
| ISC-11 | visual | screenshot the same slide from both paths and difference them | < 0.01% of pixels | Chromium, ImageMagick `compare` | derived: no fidelity cost |
| ISC-12 | export | export with `org-ppt-node-program` unresolvable, then render offline | runtime present, math typeset | `make test`, Chromium | literal |
| ISC-13 | unit | subset stylesheet is shorter than the full one and holds exactly 6 faces | 6, shorter | `make test` | derived: no corruption |
| ISC-14 | diff | export a math-free deck at the original commit and at HEAD | identical but Org anchor ids | `git archive`, `cmp -l` | literal |

## Decisions

- 2026-09-01 — Vendor KaTeX 0.16.22 into `assets/katex/` rather than fetching at
  export time. Export must work offline, and a pinned copy makes a deck's rendering
  reproducible years later. Upstream MIT `LICENSE` copied alongside.
- 2026-09-01 — Ship only `.woff2` fonts (296 KB across 20 faces), dropping upstream's
  `.woff` and `.ttf` fallbacks. Every browser that can run the deck's ES6 runtime
  already reads woff2, so the fallbacks are dead weight in a file meant to travel.
- 2026-09-01 — Inline all 20 font faces rather than a "common" subset. A missing
  face degrades silently to a system serif, which is exactly the failure the
  Principles forbid; correctness beats the ~130 KB a subset would save.
- 2026-09-01 — Reuse Org's `mathjax` passthrough as the transport. It already emits
  `\(…\)` and raw `\begin{…}` environments, which are KaTeX auto-render's default
  delimiters, so no new parsing is introduced. The MathJax CDN never appears because
  `org-ppt-template` fully replaces `org-html-template`.
- 2026-09-01 — Gate the KaTeX payload on a dynamic flag set by the math translators
  rather than scanning the rendered HTML, so a `$` inside a source block cannot
  trigger a 600 KB payload.

## Verification

- ISC-1 — `org-ppt-test-latex-probe-checks-every-program`, `-keeps-a-complete-toolchain`
- ISC-2 — `org-ppt-test-latex-downgrade-names-the-missing-program`
- ISC-3 — Chromium screenshot `build/slide-11.png`, DNS mapped to 0.0.0.0, KaTeX glyphs typeset
- ISC-4 — `org-ppt-test-katex-css-is-self-contained` with planted positive; 0 hits for `url(fonts/`
- ISC-5 — math-free demo export byte-identical to pre-change baseline (85202 bytes, delta 0)
- ISC-6 — `org-ppt-test-katex-is-the-default`
- ISC-7 — `make test` 33/33; demo slide count 17 before and after the change
- ISC-8 — `--dump-dom` with resolver blackholed: zero console errors, 7 rendered KaTeX nodes

## Learning

- learned: Org's `mathjax` setting is a pure pass-through — it emits `\(…\)` and
  leaves `\begin{…}` environments untouched. That is exactly KaTeX auto-render's
  default delimiter set, so the whole feature needed no parser of its own.
- learned: auto-render ignores `pre` and `code` by default, so shell snippets
  holding `$HOME` and `$5` survive a math-enabled deck untouched. Verified on a
  slide built to trip it.
- criterion-now: an emptiness assertion in this repo ships with a planted
  positive beside it, after the font-inlining check would have passed just as
  cleanly against a stale pattern.


## Decisions (iteration 2)

- 2026-09-01 — Typeset at export with Node rather than subsetting blindly. Knowing
  which faces a deck needs means knowing what KaTeX drew, which means running
  KaTeX; once it has run, shipping its output costs nothing and the 276 KB
  runtime can go too. The saving is therefore a consequence of the design, not a
  guess about which faces are common.
- 2026-09-01 — Subset by family, not by individual face. Weight and style would
  need per-class parsing of `font-weight` and `font-style`, and a missing bold
  face is synthesised by the browser rather than lost, so the extra precision
  buys little against a real chance of dropping something.
- 2026-09-01 — Collect math during transcoding and render the whole deck in one
  Node call from `org-ppt-template`. Per-fragment calls would pay Node's startup
  for every equation on the deck.
- 2026-09-01 — Keep the runtime path intact for machines without Node instead of
  making Node a requirement. The point of the previous iteration was that math
  needs nothing installed; trading a TeX dependency for a Node one would undo it.

## Learning (iteration 2)

- refuted: reading a whole CSS selector for class names looked equivalent to
  reading the element it targets. It is not — every KaTeX rule is written
  `.katex .something`, so `katex` mapped to every family, every rendered fragment
  carried that class, and the subset kept all twenty faces while reporting
  success. Only the byte count exposed it.
- learned: a `replace-regexp-in-string` replacement function must not disturb the
  match data. The caller splices on it afterwards, so a `string-match` inside the
  lambda silently corrupts the result — here the stylesheet grew instead of
  shrinking, and 20 faces became 26. Two further lambdas in the file had the same
  shape, including the image embedder, and were fixed with it.
- learned: `/tmp` was swept mid-run and an export against the vanished fixture
  produced an empty deck that read exactly like a code defect. Fixtures now live
  in the session scratchpad. The tell was that the failure reproduced with the
  feature disabled.

## Verification (iteration 2)

- ISC-9 — exported deck: 0 `renderMathInElement`, 10 `class="katex` nodes
- ISC-10 — 6 `@font-face` blocks (Main ×4, Math ×2) against 20 in the full sheet
- ISC-11 — `compare -metric AE`: 49.6 of 1.44M pixels differ, 3.4e-05, antialiasing only
- ISC-12 — `org-ppt-test-math-deck-falls-back-to-the-runtime`; Chromium screenshot of the fallback deck
- ISC-13 — `org-ppt-test-katex-css-subset-keeps-only-what-was-asked`; sweep of all three replacement lambdas
- ISC-14 — `cmp -l` against a `git archive` of 1607ba4: 21 bytes differ, all inside three Org-generated anchor ids
- Suite — `make test` 39/39; demo deck 269,355 bytes against 733,491 before

## Remaining Work

- [ ] Subset by face rather than by family — a deck using no bold would drop two
      more faces. Not an ISC of this run because the browser synthesises a missing
      weight, so the remaining waste is bounded and visible, unlike a missing family.
