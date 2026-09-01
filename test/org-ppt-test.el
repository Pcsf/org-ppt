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

(provide 'org-ppt-test)

;;; org-ppt-test.el ends here
