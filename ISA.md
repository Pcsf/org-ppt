---
phase: complete
progress: 9/9
task: "Font sizing, title background from a PowerPoint template, printed notes, columns with headings"
slug: org-ppt
iteration: 3
started: 2026-09-01T00:00:00Z
updated: 2026-09-18T00:00:00Z
principal_stated_goal: "this project is work fine. However, there are some improvementes I'd like to ask.
1. make it possible to enable the font size to auto adjust to fite in the slide, manually change the font size easely direct in the .org file (it can be in the header or the file) or use the default.
2. make it possible to add a specific background image for the first slide which can be imported from a Powerpoint template
3. Option to include the speaker notes as footnote of the corresponding slide once the presentation is printed using Ctrl-p
4. Fix an issue regarding the #+begin_comumns block sections: when a ** <text> followed by text do not get organized in columns. It works with text without sessions (like ** <session name>) only."
principal_stated_goal_source: prompt
principal_stated_goal_signal: 1
principal_stated_goal_locked: 2026-09-18T00:00:00Z
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

---

# Iteration 3 — fitting text, branded title slides, printable notes, columns that hold headings

## Problem (iteration 3)

Four things the deck cannot do that a person writing a real talk needs.

1. Every type size is a constant in the stylesheet. A slide with one paragraph
   too many overflows a fixed 1280x720 frame and the overflow is simply clipped,
   with no way to shrink that slide and no way to set a different base size for
   the deck from the Org file.
2. A corporate deck opens on a branded title slide. org-ppt has no way to put a
   background image behind the title, and the brand asset almost always arrives
   as a `.pptx` or `.potx` template rather than a loose image file.
3. Speaker notes exist and are excellent on screen, and vanish entirely from the
   printed handout — exactly where a presenter wants them.
4. `#+BEGIN_COLUMNS` breaks the moment a column contains a headline. Org parses
   outline structure before block structure, so a `**` line inside the block ends
   the section, the block never closes, and the `#+BEGIN_COLUMN` lines render as
   literal paragraph text with `_` turned into subscripts. Reproduced before any
   code was read: exported HTML carries `#+BEGIN<sub>COLUMNS</sub>`.

## Vision (iteration 3)

You write the talk. The text fits the slide without you counting lines, the
title slide carries your company's own background straight out of the template
IT gave you, `Ctrl-P` produces the handout you would actually hand out, and the
two-column layout holds headings like any other layout would.

## Out of Scope (iteration 3)

Reading text, placeholders or layouts from a PowerPoint template (background
image only), per-element font control, reflowing content across slides when it
does not fit, a notes-only handout mode, and making Org parse headlines inside
blocks in general.

## Claims (iteration 3)

- [x] ISC-15: `#+ORG_PPT_FONT_SCALE:` in the document header changes the type
      size of the whole deck, accepting a multiplier (`0.9`), a percentage
      (`90%`) or an explicit base (`24px`).
- [x] ISC-16: A `:PPT_FONT_SCALE:` property changes one slide only, leaving
      every other slide at the deck size.
- [x] ISC-17: With `#+ORG_PPT_AUTOFIT: t`, a slide whose content overflows the
      frame is shrunk until it fits, and a slide that already fits is left at
      the deck size — verified by measuring the rendered DOM in a real browser.
- [x] ISC-18: `#+ORG_PPT_TITLE_BG:` puts an image behind the title slide,
      embedded as a data URI like every other asset.
- [x] ISC-19: The same keyword accepts a `.pptx`/`.potx` template and pulls the
      title background out of it, with `file.pptx::member` naming a member
      explicitly and `org-ppt-list-pptx-images` showing what is available.
- [x] ISC-20: With `#+ORG_PPT_PRINT_NOTES: t`, printing puts each slide's
      speaker notes in a band under that slide, one slide per page, and the
      screen presentation is unchanged.
- [x] ISC-21: A headline inside `#+BEGIN_COLUMNS` renders as a heading inside
      its column; the columns grid is produced and no `#+BEGIN_COLUMN` literal
      survives into the output.
- [x] ISC-22: Anti: a deck that sets none of the new keywords RENDERS
      pixel-for-pixel as it did before this iteration, so nobody pays for a
      feature they did not ask for. Restated mid-run: "byte-for-byte" as first
      written is false and stays refuted below — the HTML necessarily differs.
      Rendering, which is what the claim was protecting, is identical.
- [x] ISC-23: Anti: the rewrite that makes headlines work inside columns never
      touches a headline outside a columns block, and never touches text inside
      `#+BEGIN_SRC`, `#+BEGIN_EXAMPLE` or `#+BEGIN_EXPORT`.

## Test Strategy (iteration 3)

| isc | type | check | threshold | tool | anchors_to |
|-----|------|-------|-----------|------|------------|
| ISC-15 | unit | ERT asserts the custom property reaches `:root` for each accepted spelling | 3/3 forms | `make test` | literal |
| ISC-16 | unit | ERT asserts the inline style lands on that section and no other | 1 of N | `make test` | literal |
| ISC-17 | runtime | Chromium reads back `scrollHeight` vs `clientHeight` and the computed font size per slide | overflowing slide fits, fitting slide unchanged | headless Chromium `--dump-dom` / evaluate | literal |
| ISC-18 | export | grep the title section for the background custom property carrying a data URI | 1 match | `grep` | literal |
| ISC-19 | integration | build a real `.pptx` zip fixture, export, assert the member's bytes land in the deck | image bytes present | `make test` | literal |
| ISC-20 | visual | print-to-PDF with notes on; page count and note text on the right page | pages == slides, note under its slide | headless Chromium `--print-to-pdf`, `pdftotext` | literal |
| ISC-21 | export | export the repro deck; assert grid + column divs and zero literal block text | 2 columns, 0 literals | `make test` | literal |
| ISC-22 | diff | export the demo deck at HEAD~ and at HEAD | identical | `git stash`, `cmp` | derived: no cost when unused |
| ISC-23 | unit | ERT plants a headline outside columns and one inside a SRC block | both untouched | `make test` | derived: bounded rewrite |

## Decisions (iteration 3)

- 2026-09-18 — Express every size on a slide as an exact ratio of one base
  (`calc(46em / 26)`), not as a decimal em. One custom property then moves the
  whole slide, which is what makes the document keyword, the per-slide property
  and the autofit runtime the same knob rather than three. Decimal ems were
  tried first and shifted glyphs by six ten-thousandths of a pixel — invisible,
  but enough to change antialiasing on every edge and destroy the parity proof.
- 2026-09-18 — Autofit bisects the multiplier instead of stepping it down.
  Fitting is monotonic, so nine reflows land on the largest readable size
  regardless of how badly a slide overflows; stepping would cost up to twenty
  per slide and still be coarser.
- 2026-09-18 — Autofit only ever shrinks, and never past half the deck size.
  Growing sparse slides would make a two-line slide shout, and a slide scaled
  below half is unreadable from the back of a room, which is not a fit.
- 2026-09-18 — Fix headlines-in-columns before the parse, not during it. Org
  resolves outline structure first, so by the time a transcoder sees the tree
  the block is already gone; there is nothing left to repair. The rewrite runs
  on the buffer copy Org exports from, only inside balanced COLUMNS regions,
  and skips SRC/EXAMPLE/EXPORT — so the user's file is never touched and a
  quoted example of the syntax stays quoted.
- 2026-09-18 — Bind the before-parsing hook for this export only, and pick the
  variable name at load time. Org 9.6 renamed it and aliased the old name;
  binding the new name unconditionally would make the rewrite silently do
  nothing on the Org 9.3 this package claims to support.
- 2026-09-18 — Walk a PowerPoint package's relationship chain (slide, then its
  layout, then the master) and take the largest picture at the shallowest level
  that has one. A template carries no slides at all, and a logo is a picture
  too, so neither "the first image" nor "the biggest image in the package" is
  right. The heuristic is documented and `::member` overrides it outright.
- 2026-09-18 — Ship a throwaway `examples/brand.potx` rather than documenting
  the template path and leaving it untested by the demo. It also holds a small
  logo, so the demo deck exercises the disambiguation the walk exists for; a
  template with one picture in it would have proved nothing.
- 2026-09-18 — `make verify` screenshots one slide per feature and passes
  `--force-prefers-reduced-motion`. The list is a variable so a design change
  can be eyeballed anywhere without editing the Makefile.
- 2026-09-18 — Emit the `@page` rule from the exporter rather than the
  stylesheet. `@page` cannot read a custom property, and the page has to follow
  the stage — which also fixed 4:3 decks, which had always printed 16:9.

## Learning (iteration 3)

- refuted: "a deck that changes nothing exports byte-for-byte as before". It
  cannot — the stage gained two data attributes and the `@page` rule moved out
  of the stylesheet. The claim was written for the wrong invariant. What
  actually protects the user is rendered parity, which now holds exactly:
  0 differing pixels across five demo slides.
- learned: the measuring pass restarted the current slide's entrance animation,
  because `.is-measuring` carried `animation: none !important` and toggling it
  replays the animation from opacity 0. Invisible in the DOM, invisible in
  computed styles, and obvious the moment a screenshot was looked at — the deck
  came out near-white with the title barely legible. Scoping the rule to
  `:not(.is-current)` fixed it.
- learned: a headless screenshot of this deck is a race against a 0.28 s fade,
  and the race was silently losing. Two captures of the same page disagreed by
  1.4% of pixels for no reason in the code. `--force-prefers-reduced-motion`
  makes it deterministic, and the stylesheet already honoured that media query.
- criterion-now: a visual claim in this repo closes on pixels that were looked
  at, not on computed styles that were read back. Computed style reported the
  background image, its size, and the correct text colour on a slide that
  rendered as a blank white page.

## Verification (iteration 3)

- ISC-15 — `org-ppt-test-font-scale-spellings`; deck reads 23.4 px for 0.9 of 26
- ISC-16 — `org-ppt-test-per-slide-font-scale`; that slide 15.6 px, others 23.4
- ISC-17 — Chromium DOM readback: overflow 209 px → 1 px at fit 0.7217, the two
  fitting slides untouched at 23.4 px
- ISC-18 — `org-ppt-test-title-background-image`; screenshot shows the image
  with the 0.4 wash and legible title text
- ISC-19 — `org-ppt-test-title-background-from-a-powerpoint-template` (the
  logo is not mistaken for the background), `-names-a-template-member`
- ISC-20 — `--print-to-pdf`: 5 pages for 5 slides at 1280×1010, each slide's
  notes under it; page 5 rendered and viewed
- ISC-21 — `org-ppt-test-columns-hold-headings`; the repro deck that produced
  `#+BEGIN<sub>COLUMNS</sub>` now produces the grid
- ISC-22 — `compare -metric AE` on demo slides 1, 4, 9, 13, 17 at HEAD vs the
  working tree: 0 differing pixels each
- ISC-23 — `org-ppt-test-column-rewrite-is-bounded`,
  `-leaves-the-source-alone`, `-unclosed-columns-block-is-reported`
- Suite — `make test` 62/62; `make verify` clean
- Demo — every feature and every fixed defect is exercised by `examples/demo.org`
  and visible in the exported deck: title background from `examples/brand.potx`
  (slide 1), headings inside columns (12, 13), a slide autofit shrank from 266 px
  of overflow to 0 at fit 0.7773 (20) beside one it left alone (21), a slide sized
  by hand (22), and 6 slides whose notes reach the handout (`make pdf`, 24 pages)

## Remaining Work (iteration 3)

- [ ] Autofit measures once, at load. A deck whose content changes afterwards
      (a Babel result re-rendered, a web font arriving very late) keeps the
      size it was measured at. `window.orgPpt.refit()` re-runs it by hand.
- [ ] Printed notes longer than the band are clipped rather than flowed onto a
      second page. `#+ORG_PPT_PRINT_NOTES_HEIGHT` is the escape hatch.
