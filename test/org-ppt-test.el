;;; org-ppt-test.el --- ERT suite for org-ppt  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l test/org-ppt-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-ppt)

(defconst org-ppt-test--1x1-png
  (concat "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
          "AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  "A one-pixel PNG, base64 encoded, for the image-embedding tests.")

(defmacro org-ppt-test--with-deck (content &rest body)
  "Export CONTENT as a deck and run BODY with `html' bound to the result.
A scratch directory is used so tests can drop image files next to the
Org source, which is what the data-URI code resolves against."
  (declare (indent 1) (debug t))
  `(let* ((dir (make-temp-file "org-ppt-test" t))
          (org (expand-file-name "deck.org" dir))
          (default-directory dir))
     (unwind-protect
         (progn
           (with-temp-file org (insert ,content))
           (let* ((buf (find-file-noselect org))
                  (out (with-current-buffer buf (org-ppt-export-to-html)))
                  (html (with-temp-buffer
                          (insert-file-contents out)
                          (buffer-string))))
             (kill-buffer buf)
             (ignore html)
             ,@body))
       (delete-directory dir t))))

(defun org-ppt-test--count (regexp html)
  "Return how many times REGEXP occurs in HTML."
  (let ((n 0) (start 0))
    (while (string-match regexp html start)
      (setq n (1+ n) start (match-end 0)))
    n))

(defconst org-ppt-test--potx
  (concat "UEsDBBQAAAAIADaHMl2Zlz4BEAAAAA4AAAAhAAAAcHB0L3NsaWRlTGF5b3V0cy"
          "9zbGlkZUxheW91dDEueG1ssymwKs5J8UmszC8t0bcDAFBLAwQUAAAACAA2hzJd"
          "3vrgAKMAAACBAQAALAAAAHBwdC9zbGlkZUxheW91dHMvX3JlbHMvc2xpZGVMYX"
          "lvdXQxLnhtbC5yZWxzvZA9DsIwDEavEvkAcdqBATXtwtIVcYGQumlE86MkILg9"
          "WZCo1IGJ0fan9z25G55uZQ9K2QYvoeEChr4706pKXeTFxsxqwmcJSynxiJj1Qk"
          "5lHiL5eplDcqrUMRmMSt+UIWyFOGD6ZsCWycZJQhqnBtjlFekXdphnq+kU9N2R"
          "LzsVaF3trkCVDBUJnKOjySpcgwk8egO4L9H+Q+JqPgq4eW7/BlBLAwQUAAAACA"
          "A2hzJd58H5w1gAAABxAAAAEAAAAHBwdC9tZWRpYS9iZy5wbmfrDPBz5+WS4mJg"
          "YOD19HAJAtIOQKzCwQQkt+WtPgqkLDxdHEMqbr0978jJwMDBsqE7zWRxPNv8Qw"
          "ms0878U1PABQqCK7UORDeunHYWaAaDp6ufyzqnhCYAUEsDBBQAAAAIADaHMl3d"
          "JU2pRAAAAEkAAAASAAAAcHB0L21lZGlhL2xvZ28ucG5n6wzwc+flkuJiYGDg9f"
          "RwCQLSLCDMwQQk1SZzagIpAU8Xx5CKW8k/zh9gcOc5UsiwbjL/R4u4HkGgHIOn"
          "q5/LOqeEJgBQSwECFAMUAAAACAA2hzJdmZc+ARAAAAAOAAAAIQAAAAAAAAAAAA"
          "AAgAEAAAAAcHB0L3NsaWRlTGF5b3V0cy9zbGlkZUxheW91dDEueG1sUEsBAhQD"
          "FAAAAAgANocyXd764ACjAAAAgQEAACwAAAAAAAAAAAAAAIABTwAAAHBwdC9zbG"
          "lkZUxheW91dHMvX3JlbHMvc2xpZGVMYXlvdXQxLnhtbC5yZWxzUEsBAhQDFAAA"
          "AAgANocyXefB+cNYAAAAcQAAABAAAAAAAAAAAAAAAIABPAEAAHBwdC9tZWRpYS"
          "9iZy5wbmdQSwECFAMUAAAACAA2hzJd3SVNqUQAAABJAAAAEgAAAAAAAAAAAAAA"
          "gAHCAQAAcHB0L21lZGlhL2xvZ28ucG5nUEsFBgAAAAAEAAQAJwEAADYCAAAAAA"
          "==")
  "A minimal PowerPoint template, base64 encoded.
It holds one layout relating to two pictures -- a large background and a
small logo -- which is the shape the background walk has to disambiguate.")

(defconst org-ppt-test--potx-background
  (concat "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAkCAIAAAC2bqvFAAAAOElEQVR42u3PQQkA"
          "AAgEsItmNKNfBp/CYAWWzP4mICAgICAgICAgICAgICAgICAgICAgICAgIHBTeSrA"
          "W4Gpls0AAAAASUVORK5CYII=")
  "The picture `org-ppt-test--potx' should be read as its background.")

(defun org-ppt-test--drop-potx (name)
  "Write the test PowerPoint template to NAME in `default-directory'."
  (with-temp-file name
    (set-buffer-multibyte nil)
    (insert (base64-decode-string org-ppt-test--potx))))

(defun org-ppt-test--drop-png (name)
  "Write the test PNG to NAME in `default-directory'."
  (with-temp-file name
    (set-buffer-multibyte nil)
    (insert (base64-decode-string org-ppt-test--1x1-png))))


;;;; Structure

(ert-deftest org-ppt-test-headline-becomes-slide ()
  "Each headline at the slide level produces one slide section."
  (org-ppt-test--with-deck "#+TITLE: T\n\n* One\ntext\n* Two\ntext\n"
    (should (= 3 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should (string-match-p "data-title=\"One\"" html))
    (should (string-match-p "data-title=\"Two\"" html))))

(ert-deftest org-ppt-test-title-slide ()
  "The title slide is generated from the document metadata."
  (org-ppt-test--with-deck "#+TITLE: A talk\n#+SUBTITLE: sub\n#+AUTHOR: Me\n\n* One\n"
    (should (string-match-p "opp-slide opp-title" html))
    (should (string-match-p "<h1>A talk</h1>" html))
    (should (string-match-p "opp-subtitle\">sub" html))
    (should (string-match-p "opp-author\">Me" html))))

(ert-deftest org-ppt-test-title-slide-can-be-suppressed ()
  "`ppt-title:nil' removes the generated opening slide."
  (org-ppt-test--with-deck "#+TITLE: A talk\n#+OPTIONS: ppt-title:nil\n\n* One\n"
    (should-not (string-match-p "opp-slide opp-title" html))
    (should (= 1 (org-ppt-test--count "<section class=\"opp-slide" html)))))

(ert-deftest org-ppt-test-slide-level-creates-dividers ()
  "Headlines above the slide level become full-bleed dividers."
  (org-ppt-test--with-deck
      "#+ORG_PPT_SLIDE_LEVEL: 2\n#+OPTIONS: ppt-title:nil\n\n* Part\n** A\n** B\n"
    (should (= 1 (org-ppt-test--count "opp-slide opp-section" html)))
    (should (= 3 (org-ppt-test--count "<section class=\"opp-slide" html)))
    ;; A divider must be a sibling of its slides, never their container.
    (should-not (string-match-p "opp-section[^<]*<section" html))))

(ert-deftest org-ppt-test-section-tag ()
  "The :section: tag forces a divider at the slide level."
  (org-ppt-test--with-deck "#+OPTIONS: ppt-title:nil\n\n* Break                :section:\n"
    (should (string-match-p "opp-slide opp-section" html))))

(ert-deftest org-ppt-test-deeper-headlines-stay-inside-the-slide ()
  "Headlines below the slide level render as in-slide headings."
  (org-ppt-test--with-deck "#+OPTIONS: ppt-title:nil\n\n* Slide\n** Sub\ntext\n"
    (should (= 1 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should (string-match-p "<h3>Sub</h3>" html))))

(ert-deftest org-ppt-test-no-agenda-by-default ()
  "A deck gets no agenda slide unless the document asks for one."
  (org-ppt-test--with-deck "#+OPTIONS: ppt-title:nil\n\n* One\n* Two\n"
    (should (= 2 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should-not (string-match-p "data-title=\"Agenda\"" html))))

(ert-deftest org-ppt-test-agenda-lists-sections-not-slides ()
  "With dividers in play, the agenda lists sections rather than every slide."
  (org-ppt-test--with-deck
      (concat "#+ORG_PPT_SLIDE_LEVEL: 2\n#+OPTIONS: toc:t ppt-title:nil\n\n"
              "* Part one\n** A\n** B\n* Part two\n** C\n")
    (let ((agenda (progn
                    (string-match
                     "data-title=\"Agenda\">\\(\\(?:.\\|\n\\)*?\\)</section>" html)
                    (match-string 1 html))))
      (should (string-match-p "Part one" agenda))
      (should (string-match-p "Part two" agenda))
      (should-not (string-match-p "<li>A</li>" agenda)))))


;;;; Speaker notes

(ert-deftest org-ppt-test-notes-block ()
  "A NOTES block lands in an aside inside the slide, not in its body."
  (org-ppt-test--with-deck
      "#+OPTIONS: ppt-title:nil\n\n* Slide\nvisible\n#+BEGIN_NOTES\nsecret\n#+END_NOTES\n"
    (should (string-match-p "<aside class=\"opp-notes\">" html))
    (should (string-match-p "secret" html))
    (let ((body (progn (string-match
                        "<div class=\"opp-body\">\\(\\(?:.\\|\n\\)*?\\)</div>" html)
                       (match-string 1 html))))
      (should (string-match-p "visible" body))
      (should-not (string-match-p "secret" body)))))

(ert-deftest org-ppt-test-notes-tag ()
  "A :notes: subtree under a slide is speaker-only and never its own slide."
  (org-ppt-test--with-deck
      "#+OPTIONS: ppt-title:nil\n\n* Slide\nvisible\n** Reminder      :notes:\nsecret\n"
    (should (= 1 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should (string-match-p "<aside class=\"opp-notes\">" html))
    (should-not (string-match-p "<h3>Reminder</h3>" html))))


;;;; Fragments

(ert-deftest org-ppt-test-fragment-list ()
  "`#+ATTR_PPT: :fragment t' makes each item of that list a step."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n* S\n"
              "#+ATTR_PPT: :fragment t\n- a\n- b\n\nplain paragraph\n\n- c\n- d\n")
    ;; Only the marked list steps; the unmarked one is shown at once.
    (should (= 2 (org-ppt-test--count "<li class=\"fragment" html)))
    (should (= 4 (org-ppt-test--count "<li" html)))))

(ert-deftest org-ppt-test-fragment-lists-globally ()
  "`#+OPTIONS: ppt-frag:t' steps every list in the document."
  (org-ppt-test--with-deck "#+OPTIONS: ppt-title:nil ppt-frag:t\n\n* S\n- a\n- b\n"
    (should (= 2 (org-ppt-test--count "<li class=\"fragment" html)))))

(ert-deftest org-ppt-test-fragment-block ()
  "A FRAGMENT block becomes a single revealed step."
  (org-ppt-test--with-deck
      "#+OPTIONS: ppt-title:nil\n\n* S\n#+BEGIN_FRAGMENT\nlater\n#+END_FRAGMENT\n"
    (should (string-match-p "<div class=\"fragment\">" html))))


;;;; Special blocks

(ert-deftest org-ppt-test-special-blocks ()
  "The presentation blocks map to their layout classes."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n* S\n"
              "#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\nleft\n#+END_COLUMN\n"
              "#+BEGIN_COLUMN\nright\n#+END_COLUMN\n#+END_COLUMNS\n"
              "#+BEGIN_NOTE\nn\n#+END_NOTE\n#+BEGIN_WARNING\nw\n#+END_WARNING\n")
    (should (string-match-p "<div class=\"opp-columns\">" html))
    (should (= 2 (org-ppt-test--count "<div class=\"opp-column\">" html)))
    (should (string-match-p "<div class=\"opp-callout\">" html))
    (should (string-match-p "opp-callout opp-warning" html))))


;;;; Self-containment

(ert-deftest org-ppt-test-embeds-images ()
  "Local images become data URIs so the file stands alone."
  (org-ppt-test--with-deck
      (progn (org-ppt-test--drop-png "pic.png")
             "#+OPTIONS: ppt-title:nil\n\n* S\n[[file:pic.png]]\n")
    (should (string-match-p "src=\"data:image/png;base64," html))
    (should-not (string-match-p "src=\"pic.png\"" html))))

(ert-deftest org-ppt-test-embedding-can-be-disabled ()
  "`ppt-embed:nil' leaves image references as plain relative paths."
  (org-ppt-test--with-deck
      (progn (org-ppt-test--drop-png "pic.png")
             "#+OPTIONS: ppt-title:nil ppt-embed:nil\n\n* S\n[[file:pic.png]]\n")
    (should (string-match-p "src=\"pic.png\"" html))
    (should-not (string-match-p "data:image/png" html))))

(ert-deftest org-ppt-test-no-external-resources ()
  "A deck must never reach the network to render."
  (org-ppt-test--with-deck "#+TITLE: T\n\n* S\ntext\n#+BEGIN_SRC sh\necho hi\n#+END_SRC\n"
    (should-not (string-match-p "<link[^>]*rel=\"stylesheet\"" html))
    (should-not (string-match-p "<script[^>]*\\bsrc=" html))
    (should-not (string-match-p "https?://[^\"'< ]*\\.\\(js\\|css\\)" html))
    ;; The assets themselves must actually be present, not merely referenced.
    (should (string-match-p "\\.opp-slide" html))
    (should (string-match-p "window\\.orgPpt" html))))

(ert-deftest org-ppt-test-document-shell ()
  "The export is a complete HTML document with the expected shell."
  (org-ppt-test--with-deck "#+TITLE: My talk\n\n* S\n"
    (should (string-prefix-p "<!DOCTYPE html>" html))
    (should (string-match-p "<title>My talk</title>" html))
    (should (string-match-p "data-theme=\"light\"" html))
    (should (string-match-p "id=\"opp-chrome-template\"" html))
    (should (string-suffix-p "</html>\n" html))))


;;;; Options

(ert-deftest org-ppt-test-aspect-ratio ()
  "The stage geometry follows #+ORG_PPT_ASPECT."
  (org-ppt-test--with-deck "#+ORG_PPT_ASPECT: 4:3\n\n* S\n"
    (should (string-match-p "--stage-w:1024px;--stage-h:768px" html)))
  (org-ppt-test--with-deck "* S\n"
    (should (string-match-p "--stage-w:1280px;--stage-h:720px" html))))

(ert-deftest org-ppt-test-theme-and-accent ()
  "Theme and accent keywords reach the document."
  (org-ppt-test--with-deck "#+ORG_PPT_THEME: dark\n#+ORG_PPT_ACCENT: #FF0000\n\n* S\n"
    (should (string-match-p "data-theme=\"dark\"" html))
    (should (string-match-p "--accent:#FF0000" html))))

(ert-deftest org-ppt-test-footer-and-transition ()
  "Footer text and transition reach the runtime."
  (org-ppt-test--with-deck
      "#+ORG_PPT_FOOTER: ACME internal\n#+ORG_PPT_TRANSITION: slide\n\n* S\n"
    (should (string-match-p "data-transition=\"slide\"" html))
    (should (string-match-p "opp-footer\">ACME internal<" html))))

(ert-deftest org-ppt-test-footer-is-escaped ()
  "Document-supplied text cannot inject markup into the deck."
  (org-ppt-test--with-deck "#+ORG_PPT_FOOTER: a <b> & c\n\n* S\n"
    (should (string-match-p "opp-footer\">a &lt;b&gt; &amp; c<" html))))


;;;; Assets

(ert-deftest org-ppt-test-assets-are-readable ()
  "The bundled assets resolve relative to the package source."
  (should (string-match-p "opp-stage" (org-ppt--asset "org-ppt.css")))
  (should (string-match-p "orgPpt" (org-ppt--asset "org-ppt.js"))))

(ert-deftest org-ppt-test-mime-types ()
  "Extension to MIME mapping covers the image formats we claim to support."
  (should (equal "image/png" (org-ppt--mime-type "a/b.PNG")))
  (should (equal "image/svg+xml" (org-ppt--mime-type "d.svg")))
  (should (equal "image/jpeg" (org-ppt--mime-type "d.jpeg")))
  (should-not (org-ppt--mime-type "d.exe"))
  (should-not (org-ppt--mime-type "noext")))


;;;; Math

(defconst org-ppt-test--absent "org-ppt-no-such-program"
  "A program name that is guaranteed not to be on PATH.")

(defun org-ppt-test--messages-of (fn)
  "Call FN and return everything it wrote to the message log."
  (with-current-buffer (messages-buffer)
    (let ((start (point-max)))
      (funcall fn)
      (buffer-substring-no-properties start (point-max)))))

(ert-deftest org-ppt-test-latex-probe-checks-every-program ()
  "A process whose second program is missing is not treated as available.
Probing only the first binary let a machine carrying TeX but not dvipng
reach the renderer and fail there instead of degrading."
  (let ((org-ppt-with-latex 'dvipng)
        (org-preview-latex-process-alist
         `((dvipng :programs ("sh" ,org-ppt-test--absent)))))
    (should (equal org-ppt-test--absent (org-ppt--missing-latex-program 'dvipng)))
    (should (eq 'katex (org-ppt--resolved-latex)))))

(ert-deftest org-ppt-test-latex-probe-keeps-a-complete-toolchain ()
  "A process with every program present is used as configured."
  (let ((org-ppt-with-latex 'dvipng)
        (org-preview-latex-process-alist '((dvipng :programs ("sh" "ls")))))
    (should-not (org-ppt--missing-latex-program 'dvipng))
    (should (eq 'dvipng (org-ppt--resolved-latex)))))

(ert-deftest org-ppt-test-latex-downgrade-names-the-missing-program ()
  "The downgrade says which binary is absent, never just that math broke."
  (let* ((org-ppt-with-latex 'imagemagick)
         (org-preview-latex-process-alist
          `((imagemagick :programs (,org-ppt-test--absent))))
         (log (org-ppt-test--messages-of #'org-ppt--resolved-latex)))
    (should (string-match-p (regexp-quote org-ppt-test--absent) log))
    (should (string-match-p "imagemagick" log))))

(ert-deftest org-ppt-test-non-process-modes-pass-through ()
  "Modes that render nothing themselves are never probed for binaries."
  (dolist (mode '(katex verbatim))
    (let ((org-ppt-with-latex mode))
      (should (eq mode (org-ppt--resolved-latex))))))

(ert-deftest org-ppt-test-katex-is-the-default ()
  "Math works on a machine with no TeX, with no configuration."
  (should (eq 'katex (default-value 'org-ppt-with-latex))))

(ert-deftest org-ppt-test-katex-css-is-self-contained ()
  "Font faces are inlined, and the relative fallbacks are dropped.
The bundled stylesheet is asserted to carry the pattern first, so a clean
result proves the rewrite ran rather than that the pattern went stale."
  (let ((raw (org-ppt--katex-asset "katex.min.css"))
        (css (org-ppt--katex-css)))
    (should (string-match-p "url(fonts/" raw))
    (should (string-match-p "truetype" raw))
    (should (string-match-p "data:font/woff2;base64," css))
    (should-not (string-match-p "url(fonts/" css))
    (should-not (string-match-p "truetype" css))))

(ert-deftest org-ppt-test-math-deck-is-prerendered ()
  "With Node present the deck ships typeset math and no runtime."
  (skip-unless (executable-find org-ppt-node-program))
  (org-ppt-test--with-deck "* S\nThe relation $E=mc^2$ holds.\n"
    (should (string-match-p "class=\"katex" html))
    (should (string-match-p "data:font/woff2;base64," html))
    (should-not (string-match-p "renderMathInElement" html))
    (should-not (string-match-p "org-ppt-math:" html))))

(ert-deftest org-ppt-test-math-deck-falls-back-to-the-runtime ()
  "Without Node the deck ships the runtime and Org's pass-through form."
  (let ((org-ppt-node-program "org-ppt-no-such-node"))
    (org-ppt-test--with-deck "* S\nThe relation $E=mc^2$ holds.\n"
      (should (string-match-p "renderMathInElement" html))
      (should (string-match-p (regexp-quote "\\(E=mc^2\\)") html))
      (should (string-match-p "data:font/woff2;base64," html))
      (should-not (string-match-p "org-ppt-math:" html)))))

(ert-deftest org-ppt-test-prerendered-deck-carries-fewer-faces ()
  "Typesetting at export time is what lets the deck drop unused faces."
  (skip-unless (executable-find org-ppt-node-program))
  (let (small)
    (org-ppt-test--with-deck "* S\nThe relation $E=mc^2$ holds.\n"
      (setq small (org-ppt-test--count "data:font/woff2" html)))
    (let ((org-ppt-node-program "org-ppt-no-such-node"))
      (org-ppt-test--with-deck "* S\nThe relation $E=mc^2$ holds.\n"
        (should (= 20 (org-ppt-test--count "data:font/woff2" html)))
        (should (< small 20))))))

(ert-deftest org-ppt-test-math-source-splits-every-delimiter ()
  "Each delimiter pair yields its source and the right display flag."
  (should (equal '("x" . nil) (org-ppt--math-source "$x$")))
  (should (equal '("x" . t) (org-ppt--math-source "$$x$$")))
  (should (equal '("x" . nil) (org-ppt--math-source "\\(x\\)")))
  (should (equal '("x" . t) (org-ppt--math-source "\\[x\\]")))
  (should (equal '("a\nb" . t) (org-ppt--math-source "$$a\nb$$"))))

(ert-deftest org-ppt-test-selector-targets-its-rightmost-compound ()
  "`.katex .mathnormal' selects mathnormal, not everything under .katex.
Reading the whole selector once made every element match every rule, so
every face was kept and the subset saved nothing."
  (should (equal '("mathnormal") (org-ppt--selector-classes ".katex .mathnormal")))
  (should (equal '("delimsizing" "size4")
                 (org-ppt--selector-classes ".katex .delimsizing.size4")))
  (should (equal '("katex") (org-ppt--selector-classes ".katex")))
  ;; A bare tag on the right falls back to the nearest classed compound.
  (should (equal '("delim-size1")
                 (org-ppt--selector-classes ".katex .delim-size1>span"))))

(ert-deftest org-ppt-test-font-detection-is-driven-by-the-classes-present ()
  "Only the faces the rendered math reaches for are reported."
  (should (equal '("KaTeX_Main")
                 (org-ppt--katex-families-used "<span class=\"katex\"></span>")))
  (let ((used (org-ppt--katex-families-used
               "<span class=\"katex\"><span class=\"mord mathnormal\"></span></span>")))
    (should (member "KaTeX_Math" used))
    (should (member "KaTeX_Main" used))
    (should-not (member "KaTeX_Fraktur" used))))

(ert-deftest org-ppt-test-katex-css-subset-keeps-only-what-was-asked ()
  "Subsetting drops the other families and leaves the stylesheet intact.
The full sheet is measured alongside, so a subset that quietly kept
everything, or one that corrupted the sheet while rewriting it, fails."
  (let ((all (org-ppt--katex-css))
        (sub (org-ppt--katex-css '("KaTeX_Main" "KaTeX_Math"))))
    (should (= 20 (org-ppt-test--count "@font-face" all)))
    (should (= 6 (org-ppt-test--count "@font-face" sub)))
    (should (< (length sub) (length all)))
    (should (string-match-p "KaTeX_Math" sub))
    (should-not (string-match-p "@font-face{font-family:KaTeX_Fraktur" sub))))

(ert-deftest org-ppt-test-math-free-deck-carries-no-katex ()
  "A deck without math pays nothing for the math feature."
  (org-ppt-test--with-deck "* S\nPlain prose only.\n"
    (should-not (string-match-p "renderMathInElement" html))
    (should-not (string-match-p "data:font/woff2" html))))

(ert-deftest org-ppt-test-deck-references-no-remote-asset ()
  "Nothing in an exported deck is fetched over the network.
Each pattern is shown matching a planted positive, so an empty result
means the deck is clean rather than that the pattern stopped working."
  (let ((planted (concat "<link rel=\"stylesheet\" href=\"https://cdn/x.css\">"
                         "<script src=\"https://cdn/x.js\"></script>"
                         "<img src=\"https://cdn/x.png\">")))
    (should (string-match-p "<link[^>]*href=\"http" planted))
    (should (string-match-p "<script[^>]*src=" planted))
    (should (string-match-p "src=\"http" planted)))
  (org-ppt-test--with-deck "* S\nThe relation $E=mc^2$ holds.\n"
    (should-not (string-match-p "<link[^>]*href=\"http" html))
    (should-not (string-match-p "<script[^>]*src=" html))
    (should-not (string-match-p "src=\"http" html))))

(ert-deftest org-ppt-test-menu-actions-take-the-dispatcher-arity ()
  "Every dispatcher entry accepts the four arguments Org funcalls it with.
`org-export-dispatch\=' passes async, subtree, visible and body-only
positionally, so a command declaring fewer raises
`wrong-number-of-arguments\=' the moment it is picked from the menu."
  (let ((entry (org-export-backend-menu (org-export-get-backend 'ppt))))
    (dolist (action (mapcar (lambda (row) (nth 2 row)) (nth 2 entry)))
      (let ((arity (func-arity action)))
        (should (functionp action))
        (should (or (eq (cdr arity) 'many) (>= (cdr arity) 4)))
        (should (<= (car arity) 4))))))

(ert-deftest org-ppt-test-file-url-escapes-whitespace ()
  "A deck path with spaces becomes a URL a browser can open."
  (should (equal (org-ppt--file-url "/tmp/space dir/my talk.html")
                 "file:///tmp/space%20dir/my%20talk.html"))
  (should (equal (org-ppt--file-url "/tmp/plain.html")
                 "file:///tmp/plain.html"))
  (should (equal (org-ppt--file-url "/tmp/a#b?c/deck.html")
                 "file:///tmp/a%23b%3Fc/deck.html")))

;;;; Type size

(ert-deftest org-ppt-test-font-scale-spellings ()
  "A multiplier, a percentage and a length each reach the document."
  (org-ppt-test--with-deck "#+ORG_PPT_FONT_SCALE: 0.8\n\n* S\n"
    (should (string-match-p "<style>:root{--opp-scale:0.8}</style>" html)))
  (org-ppt-test--with-deck "#+ORG_PPT_FONT_SCALE: 80%\n\n* S\n"
    (should (string-match-p "<style>:root{--opp-scale:0.8}</style>" html)))
  (org-ppt-test--with-deck "#+ORG_PPT_FONT_SCALE: 24px\n\n* S\n"
    (should (string-match-p "<style>:root{--opp-base:24px}</style>" html))))

(ert-deftest org-ppt-test-font-scale-rejects-nonsense ()
  "An unreadable size is reported and the deck keeps its own."
  (should-not (org-ppt--font-scale-declaration "enormous"))
  (should-not (org-ppt--font-scale-declaration ""))
  (should-not (org-ppt--font-scale-declaration nil)))

(ert-deftest org-ppt-test-per-slide-font-scale ()
  "A PPT_FONT_SCALE property resizes its own slide and no other."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n"
              "* Small\n:PROPERTIES:\n:PPT_FONT_SCALE: 0.6\n:END:\nsmall\n"
              "* Normal\nnormal\n")
    (should (= 1 (org-ppt-test--count "style=\"--opp-scale:0.6\"" html)))
    (should (string-match-p
             "data-title=\"Small\" style=\"--opp-scale:0.6\"" html))))

(ert-deftest org-ppt-test-autofit-is-opt-in ()
  "Autofit is off unless the document asks for it."
  (org-ppt-test--with-deck "* S\n"
    (should (string-match-p "data-autofit=\"0\"" html)))
  (org-ppt-test--with-deck "#+ORG_PPT_AUTOFIT: t\n\n* S\n"
    (should (string-match-p "data-autofit=\"1\"" html))))

(ert-deftest org-ppt-test-autofit-per-slide-override ()
  "The :fit: and :nofit: tags override the deck-wide setting."
  (org-ppt-test--with-deck
      "#+OPTIONS: ppt-title:nil\n\n* A          :fit:\n* B          :nofit:\n* C\n"
    (should (string-match-p "data-title=\"A\" data-autofit=\"1\"" html))
    (should (string-match-p "data-title=\"B\" data-autofit=\"0\"" html))
    (should (string-match-p "data-title=\"C\">" html))))

(ert-deftest org-ppt-test-truthy-reads-org-spellings ()
  "Keyword values arrive as text, so `nil' has to be recognised as text."
  (dolist (no '("nil" "NIL" "no" "off" "false" "0" "" nil))
    (should-not (org-ppt--truthy no)))
  (dolist (yes '("t" "yes" "on" "1" t))
    (should (org-ppt--truthy yes))))


;;;; Title background

(ert-deftest org-ppt-test-title-background-image ()
  "A plain image becomes the title background, embedded like any asset."
  (org-ppt-test--with-deck
      (progn (org-ppt-test--drop-png "bg.png")
             "#+TITLE: T\n#+ORG_PPT_TITLE_BG: bg.png\n#+ORG_PPT_TITLE_BG_DIM: 0.5\n\n* S\n")
    (should (string-match-p "opp-title opp-has-bg" html))
    (should (string-match-p "--opp-title-bg:url(data:image/png;base64," html))
    (should (string-match-p "--opp-title-dim:0.5" html))
    (should (string-match-p "--opp-title-fit:cover" html))))

(ert-deftest org-ppt-test-title-background-is-absent-by-default ()
  "A deck that asks for no background carries none of the machinery."
  (org-ppt-test--with-deck "#+TITLE: T\n\n* S\n"
    ;; The stylesheet carrying these names is inlined into every deck, so the
    ;; assertion names where a background would appear rather than scanning
    ;; the whole document and matching the CSS.
    (should-not (string-match-p "opp-slide opp-title opp-has-bg" html))
    (should-not (string-match-p "style=\"--opp-title-bg" html))))

(ert-deftest org-ppt-test-title-background-from-a-powerpoint-template ()
  "The background is pulled out of a .potx, and the logo is not mistaken for it."
  (skip-unless (executable-find org-ppt-unzip-program))
  (org-ppt-test--with-deck
      (progn (org-ppt-test--drop-potx "brand.potx")
             "#+TITLE: T\n#+ORG_PPT_TITLE_BG: brand.potx\n\n* S\n")
    (should (string-match-p
             (regexp-quote (concat "--opp-title-bg:url(data:image/png;base64,"
                                   org-ppt-test--potx-background ")"))
             html))))

(ert-deftest org-ppt-test-title-background-names-a-template-member ()
  "`::member' picks a picture outright, overriding the walk."
  (skip-unless (executable-find org-ppt-unzip-program))
  (org-ppt-test--with-deck
      (progn (org-ppt-test--drop-potx "brand.potx")
             (concat "#+TITLE: T\n"
                     "#+ORG_PPT_TITLE_BG: brand.potx::ppt/media/logo.png\n\n* S\n"))
    (should (string-match-p "--opp-title-bg:url(data:image/png;base64," html))
    (should-not (string-match-p (regexp-quote org-ppt-test--potx-background) html))))

(ert-deftest org-ppt-test-pptx-relationship-paths-are-resolved ()
  "A relationship target is resolved against the part that declares it."
  (should (equal "ppt/media/bg.png"
                 (org-ppt--pptx-resolve "ppt/slideLayouts/" "../media/bg.png")))
  (should (equal "ppt/media/bg.png"
                 (org-ppt--pptx-resolve "ppt/" "media/bg.png")))
  (should (equal "ppt/slideMasters/slideMaster1.xml"
                 (org-ppt--pptx-resolve "ppt/slideLayouts/"
                                        "../slideMasters/slideMaster1.xml"))))

(ert-deftest org-ppt-test-pptx-extension-detection ()
  "Only PowerPoint packages take the template path."
  (should (org-ppt--pptx-p "a/brand.potx"))
  (should (org-ppt--pptx-p "BRAND.PPTX"))
  (should-not (org-ppt--pptx-p "brand.png"))
  (should-not (org-ppt--pptx-p "brand")))


;;;; Printed speaker notes

(ert-deftest org-ppt-test-print-notes-is-opt-in ()
  "Notes stay off the handout unless the document asks for them."
  (org-ppt-test--with-deck "* S\n#+BEGIN_NOTES\nsecret\n#+END_NOTES\n"
    (should-not (string-match-p "<html[^>]*data-print-notes" html)))
  (org-ppt-test--with-deck
      "#+ORG_PPT_PRINT_NOTES: t\n\n* S\n#+BEGIN_NOTES\nsecret\n#+END_NOTES\n"
    (should (string-match-p "<html[^>]*data-print-notes=\"1\"" html))))

(ert-deftest org-ppt-test-print-notes-grows-the-page ()
  "The printed page grows by the notes band, and only then."
  (org-ppt-test--with-deck "* S\n"
    (should (string-match-p "@page{size:1280px 720px;margin:0}" html))
    (should-not (string-match-p ":root{--opp-notes-band" html)))
  (org-ppt-test--with-deck "#+ORG_PPT_PRINT_NOTES: t\n\n* S\n"
    (should (string-match-p "@page{size:1280px 1010px;margin:0}" html))
    (should (string-match-p "--opp-notes-band:290px" html)))
  (org-ppt-test--with-deck
      "#+ORG_PPT_PRINT_NOTES: t\n#+ORG_PPT_PRINT_NOTES_HEIGHT: 400\n\n* S\n"
    (should (string-match-p "@page{size:1280px 1120px;margin:0}" html))))

(ert-deftest org-ppt-test-printed-page-follows-the-aspect-ratio ()
  "A 4:3 deck prints 4:3 pages.
The @page rule used to be a constant in the stylesheet, so every deck
printed 16:9 whatever its stage said."
  (org-ppt-test--with-deck "#+ORG_PPT_ASPECT: 4:3\n\n* S\n"
    (should (string-match-p "@page{size:1024px 768px;margin:0}" html))))


;;;; Headings inside a columns block

(ert-deftest org-ppt-test-columns-hold-headings ()
  "A headline inside a column renders as a heading in that column.
Org ends the section at a headline, so without the pre-parse rewrite the
block never closes and its own lines reach the slide as literal text."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n* S\n"
              "#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\n** Left\nleft body\n#+END_COLUMN\n"
              "#+BEGIN_COLUMN\n** Right\nright body\n#+END_COLUMN\n#+END_COLUMNS\n")
    (should (= 1 (org-ppt-test--count "<div class=\"opp-columns\">" html)))
    (should (= 2 (org-ppt-test--count "<div class=\"opp-column\">" html)))
    (should (string-match-p "<h3>Left</h3>" html))
    (should (string-match-p "<h3>Right</h3>" html))
    (should (string-match-p "left body" html))
    ;; One slide, not three: the headlines must not have become slides.
    (should (= 1 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should-not (string-match-p "BEGIN_COLUMN" html))
    (should-not (string-match-p "BEGIN<sub>COLUMN" html))))

(ert-deftest org-ppt-test-column-heading-depth-follows-the-slide-level ()
  "A deeper headline inside a column becomes a deeper heading."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n#+ORG_PPT_SLIDE_LEVEL: 1\n\n* S\n"
              "#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\n** Two\n*** Three\n"
              "#+END_COLUMN\n#+END_COLUMNS\n")
    (should (string-match-p "<h3>Two</h3>" html))
    (should (string-match-p "<h4>Three</h4>" html))))

(ert-deftest org-ppt-test-column-heading-drops-its-tags ()
  "Tags are outline metadata and do not belong in the rendered heading."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n* S\n"
              "#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\n** Left      :sometag:\nbody\n"
              "#+END_COLUMN\n#+END_COLUMNS\n")
    (should (string-match-p "<h3>Left</h3>" html))
    (should-not (string-match-p "sometag" html))))

(ert-deftest org-ppt-test-column-rewrite-is-bounded ()
  "The rewrite touches headlines inside a columns block and nothing else.
A headline outside one still becomes an ordinary in-slide heading, and a
columns block quoted inside a literal block is left exactly as written.
The quoted block uses Org\='s comma escape, which is the only way to put a
line of stars inside a block at all -- an unescaped one ends the section
no matter what org-ppt does."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n"
              "* Real slide\n** A real in-slide heading\ntext\n"
              "* Quoting the syntax\n"
              "#+BEGIN_EXAMPLE\n,#+BEGIN_COLUMNS\n,** not a heading\n"
              ",#+END_COLUMNS\n#+END_EXAMPLE\n")
    (should (= 2 (org-ppt-test--count "<section class=\"opp-slide" html)))
    (should (string-match-p "<h3>A real in-slide heading</h3>" html))
    ;; The example block still shows the source the reader typed.
    (should (string-match-p "#\\+BEGIN_COLUMNS" html))
    (should (string-match-p "\\*\\* not a heading" html))
    (should-not (string-match-p "PPTHEADING" html))
    ;; And no columns layout was conjured out of the quoted text.
    (should-not (string-match-p "<div class=\"opp-columns\">" html))))

(ert-deftest org-ppt-test-unclosed-columns-block-is-reported ()
  "An unclosed block is named rather than silently swallowing the document."
  (let ((log (org-ppt-test--messages-of
              (lambda ()
                (with-temp-buffer
                  (insert "* S\n#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\n** Left\nbody\n")
                  (org-ppt--rewrite-column-headings))))))
    (should (string-match-p "never closed" log))))

(ert-deftest org-ppt-test-column-rewrite-leaves-the-source-alone ()
  "The rewrite runs on the buffer Org exports from, never on the user's file."
  (org-ppt-test--with-deck
      (concat "#+OPTIONS: ppt-title:nil\n\n* S\n"
              "#+BEGIN_COLUMNS\n#+BEGIN_COLUMN\n** Left\nbody\n"
              "#+END_COLUMN\n#+END_COLUMNS\n")
    (should (string-match-p "<h3>Left</h3>" html))
    (let ((source (with-temp-buffer
                    (insert-file-contents (expand-file-name "deck.org" dir))
                    (buffer-string))))
      (should (string-match-p "^\\*\\* Left$" source))
      (should-not (string-match-p "PPTHEADING" source)))))

;;; org-ppt-test.el ends here
