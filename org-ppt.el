;;; org-ppt.el --- Export Org files to self-contained HTML slide decks  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 org-ppt contributors

;; Author: org-ppt contributors
;; Maintainer: org-ppt contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: outlines, hypermedia, presentation
;; URL: https://github.com/Pcsf/org-ppt

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; org-ppt turns an Org file into ONE self-contained .html file that presents
;; like a PowerPoint slide show in any browser.  Stylesheet, runtime and every
;; image are inlined, so the deck survives being emailed, copied to a USB
;; stick, or opened from file:// on a machine with no network.
;;
;; Quick start:
;;
;;   (require 'org-ppt)
;;   ;; In an Org buffer:  C-c C-e s o   (export and open in the browser)
;;
;; Each headline at `org-ppt-slide-level' (1 by default) becomes a slide.
;; Headlines above that level become full-bleed section dividers.  Deeper
;; headlines are ordinary headings inside the slide.
;;
;; Document keywords:
;;
;;   #+ORG_PPT_THEME:      light | dark
;;   #+ORG_PPT_ACCENT:     #0F6FC5
;;   #+ORG_PPT_ASPECT:     16:9 | 4:3
;;   #+ORG_PPT_TRANSITION: fade | slide | none
;;   #+ORG_PPT_FOOTER:     text shown bottom-left on every content slide
;;   #+ORG_PPT_LOGO:       path to an image shown bottom-right
;;   #+ORG_PPT_SLIDE_LEVEL: 1
;;
;; Per-headline control, via tags and properties:
;;
;;   :section:   render this slide as a full-bleed divider
;;   :figure:    center one large figure and let it fill the frame
;;   :notes:     the subtree is speaker notes, never shown to the audience
;;   :PPT_CLASS: extra CSS classes on the slide
;;
;; Block-level helpers:
;;
;;   #+BEGIN_NOTES ... #+END_NOTES        speaker notes
;;   #+BEGIN_COLUMNS / #+BEGIN_COLUMN     side-by-side layout
;;   #+BEGIN_NOTE / #+BEGIN_WARNING       callout boxes
;;   #+BEGIN_FRAGMENT                     revealed on the next key press
;;   #+ATTR_PPT: :fragment t              before a list: reveal it item by item
;;
;; See README.org for the full manual.

;;; Code:

(require 'ox-html)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)

(defgroup org-ppt nil
  "Export Org files to self-contained HTML slide decks."
  :group 'org-export
  :prefix "org-ppt-")

;;;; Customization

(defcustom org-ppt-slide-level 1
  "Outline level whose headlines become slides.
Headlines above this level become full-bleed section dividers;
headlines below it are ordinary headings inside a slide."
  :type 'integer
  :group 'org-ppt)

(defcustom org-ppt-theme "light"
  "Default colour theme, either \"light\" or \"dark\".
The viewer can still toggle it at presentation time with `d'."
  :type '(choice (const "light") (const "dark"))
  :group 'org-ppt)

(defcustom org-ppt-accent nil
  "Accent colour as a CSS colour string, or nil for the built-in blue.
Used for slide rules, headings, list markers and section dividers."
  :type '(choice (const :tag "Built-in" nil) string)
  :group 'org-ppt)

(defcustom org-ppt-aspect "16:9"
  "Slide aspect ratio, either \"16:9\" or \"4:3\"."
  :type '(choice (const "16:9") (const "4:3"))
  :group 'org-ppt)

(defcustom org-ppt-transition "fade"
  "Slide transition: \"fade\", \"slide\" or \"none\"."
  :type '(choice (const "fade") (const "slide") (const "none"))
  :group 'org-ppt)

(defcustom org-ppt-footer nil
  "Text shown at the bottom left of every content slide, or nil."
  :type '(choice (const :tag "None" nil) string)
  :group 'org-ppt)

(defcustom org-ppt-logo nil
  "Path to a small image shown at the bottom right of content slides."
  :type '(choice (const :tag "None" nil) file)
  :group 'org-ppt)

(defcustom org-ppt-title-slide t
  "Whether to generate an opening title slide from #+TITLE and friends."
  :type 'boolean
  :group 'org-ppt)

(defcustom org-ppt-toc-title "Agenda"
  "Heading used for the generated outline slide.
The outline slide is produced only when the document asks for a table
of contents, e.g. with `#+OPTIONS: toc:t'."
  :type 'string
  :group 'org-ppt)

(defcustom org-ppt-embed-images t
  "Whether local images are inlined into the HTML as data URIs.
This is what makes the exported file self-contained.  Turn it off only
when a deck is so image-heavy that the single file becomes unwieldy."
  :type 'boolean
  :group 'org-ppt)

(defcustom org-ppt-embed-size-limit (* 6 1024 1024)
  "Warn when a single embedded file exceeds this many bytes."
  :type 'integer
  :group 'org-ppt)

(defcustom org-ppt-fragment-lists nil
  "When non-nil, every plain list is revealed one item at a time.
Leaving this nil and marking individual lists with
`#+ATTR_PPT: :fragment t' is usually the better habit."
  :type 'boolean
  :group 'org-ppt)

(defcustom org-ppt-with-latex 'katex
  "How LaTeX fragments are rendered.
Defaults to `katex', which typesets math in the browser from the KaTeX
copy bundled in assets/katex and inlined into the deck, so math needs no
TeX installation and still costs no network at display time.  The
image-rendering processes from `org-preview-latex-process-alist' are
available for decks that would rather have math as pictures; each falls
back to `katex' when its toolchain is incomplete.  MathJax is
deliberately not offered because it needs a CDN at display time."
  :type '(choice (const :tag "KaTeX, bundled and inlined" katex)
                 (const dvipng) (const dvisvgm) (const imagemagick)
                 (const verbatim))
  :group 'org-ppt)

(defcustom org-ppt-node-program "node"
  "Node executable used to typeset math at export time.
When it is on PATH the deck ships pre-rendered math and only the font
faces that math uses; when it is not, the deck ships the KaTeX runtime and
every face instead.  Both render identically — the second is the larger
file."
  :type 'string
  :group 'org-ppt)

(defcustom org-ppt-browser-function #'browse-url
  "Function called with the exported file URL to preview a deck."
  :type 'function
  :group 'org-ppt)

;;;; Version

(defconst org-ppt-version "0.1.0"
  "Version of org-ppt.")

(defun org-ppt-version ()
  "Return the org-ppt version string."
  org-ppt-version)

;;;; Assets

(defconst org-ppt--source-file (or load-file-name buffer-file-name)
  "Absolute path of this file, used to locate the bundled assets.")

(defun org-ppt--asset-directory ()
  "Return the directory holding the bundled CSS and JS."
  (let ((here (and org-ppt--source-file
                   (file-name-directory org-ppt--source-file))))
    (expand-file-name "assets" (or here default-directory))))

(defun org-ppt--asset (name)
  "Return the contents of bundled asset NAME as a string."
  (let ((path (expand-file-name name (org-ppt--asset-directory))))
    (unless (file-readable-p path)
      (error "org-ppt: missing asset %s (looked in %s)"
             name (org-ppt--asset-directory)))
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

;;;; Bundled KaTeX

(defvar org-ppt--math-mode nil
  "Resolved value of `org-ppt-with-latex' for the export in progress.")

(defvar org-ppt--math-seen nil
  "Non-nil once the export in progress has transcoded a math fragment.
Gates the KaTeX payload, so a deck without math carries none of it.")

(defvar org-ppt--math-prerender nil
  "Non-nil when this export types the math itself instead of shipping a runtime.")

(defvar org-ppt--math-queue nil
  "Math collected during transcoding, newest first.
Each entry is (TEX DISPLAY FALLBACK): the source handed to KaTeX, whether
it is display math, and the form to emit if pre-rendering falls through.")

(defun org-ppt--katex-directory ()
  "Return the directory holding the bundled KaTeX distribution."
  (expand-file-name "katex" (org-ppt--asset-directory)))

(defun org-ppt--katex-asset (name)
  "Return bundled KaTeX file NAME as a string."
  (let ((path (expand-file-name name (org-ppt--katex-directory))))
    (unless (file-readable-p path)
      (error "org-ppt: missing KaTeX asset %s (looked in %s)"
             name (org-ppt--katex-directory)))
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

(defun org-ppt--katex-font-uri (file)
  "Return bundled KaTeX font FILE as a base64 data URI, or nil if unreadable."
  (let ((path (expand-file-name file (org-ppt--katex-directory))))
    (when (file-readable-p path)
      (concat "data:font/woff2;base64,"
              (base64-encode-string
               (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (insert-file-contents-literally path)
                 (buffer-string))
               t)))))

(defun org-ppt--css-blocks (css)
  "Return CSS as a list of (SELECTOR . DECLARATIONS) pairs."
  (let ((pos 0) (blocks nil))
    (while (string-match "\\([^{}]+\\){\\([^{}]*\\)}" css pos)
      (push (cons (match-string 1 css) (match-string 2 css)) blocks)
      (setq pos (match-end 0)))
    (nreverse blocks)))

(defun org-ppt--matches (regexp string &optional group)
  "Return every match of REGEXP in STRING, or its GROUP when given."
  (let ((pos 0) (found nil))
    (while (string-match regexp string pos)
      (push (match-string (or group 0) string) found)
      (setq pos (match-end 0)))
    (nreverse found)))

(defun org-ppt--selector-classes (selector)
  "Return the classes of the element SELECTOR targets.
Only the rightmost compound matters: `.katex .mathnormal' targets an
element carrying `mathnormal', not every descendant of `.katex'.  When the
rightmost compound is a bare tag, as in `.delim-size1>span', the nearest
compound that does carry classes is used instead."
  (let ((compounds (nreverse (split-string selector "[ \t\n>+~]+" t)))
        (classes nil))
    (while (and compounds (not classes))
      (setq classes (org-ppt--matches "\\.\\([A-Za-z][A-Za-z0-9_-]*\\)"
                                      (pop compounds) 1)))
    classes))

(defun org-ppt--katex-font-rules ()
  "Return (CLASSES . FAMILIES) for every rule that selects a KaTeX face.
Read from the bundled stylesheet rather than written out here, because a
hand-kept table would drift the first time upstream adds a face.  Both the
`font-family' declarations and the `font' shorthand on `.katex' are seen."
  (let ((rules nil))
    (dolist (block (org-ppt--css-blocks (org-ppt--katex-asset "katex.min.css")))
      (let ((selector (string-trim (car block)))
            (families (delete-dups
                       (org-ppt--matches "KaTeX_[A-Za-z0-9]+" (cdr block)))))
        (when (and families (not (string-prefix-p "@" selector)))
          (dolist (part (split-string selector "," t "[ \t\n]+"))
            (let ((classes (org-ppt--selector-classes part)))
              (when classes (push (cons classes families) rules)))))))
    rules))

(defun org-ppt--katex-families-used (html)
  "Return the KaTeX font families the rendered HTML actually asks for.
A rule counts only when one element carries every class of its selector,
so a compound like `.delimsizing.size4' does not pull in a face merely
because the two classes appear on different elements."
  (let ((rules (org-ppt--katex-font-rules))
        (used nil))
    (dolist (attribute (org-ppt--matches "class=\"\\([^\"]*\\)\"" html 1))
      (let ((present (split-string attribute "[ \t\n]+" t)))
        (dolist (rule rules)
          (when (cl-every (lambda (class) (member class present)) (car rule))
            (dolist (family (cdr rule))
              (cl-pushnew family used :test #'equal))))))
    ;; `.katex' itself sets KaTeX_Main through the font shorthand, so a deck
    ;; with any math reaches it; the floor only covers a deck with none.
    (or used (list "KaTeX_Main"))))

(defun org-ppt--katex-css (&optional families)
  "Return the KaTeX stylesheet with its font faces inlined.
With FAMILIES, keep only the faces belonging to those families and drop
the rest, which is what makes a deck carry the four or five faces it uses
instead of all twenty.  Nil keeps every face.

Upstream lists woff2, woff and ttf for each face.  Only woff2 is bundled
and inlined; the other two are dropped rather than left as broken
relative URLs, since any browser that can run the deck reads woff2."
  (let ((css (org-ppt--katex-asset "katex.min.css")))
    (when families
      (setq css (replace-regexp-in-string
                 "@font-face{[^{}]*}"
                 (lambda (face)
                   ;; save-match-data is load-bearing: the caller splices on
                   ;; the match data this lambda would otherwise clobber.
                   (let ((family (save-match-data
                                   (when (string-match "KaTeX_[A-Za-z0-9]+" face)
                                     (match-string 0 face)))))
                     (if (member family families) face "")))
                 css t t)))
    (setq css (replace-regexp-in-string
               ",url(fonts/[^)]+\\.\\(?:woff\\|ttf\\)) format(\"[^\"]*\")"
               "" css t t))
    (replace-regexp-in-string
     "url(fonts/\\([^)]+\\.woff2\\))"
     (lambda (m)
       (let* ((file (match-string 1 m))
              (uri (save-match-data
                     (org-ppt--katex-font-uri (concat "fonts/" file)))))
         (if uri (concat "url(" uri ")") m)))
     css t t)))

(defun org-ppt--katex-scripts ()
  "Return the KaTeX runtime and the call that typesets the deck.
Emitted at the end of the body, before the presentation runtime, so math
has its final size before any slide is measured."
  (concat "<script>\n" (org-ppt--katex-asset "katex.min.js") "\n</script>\n"
          "<script>\n" (org-ppt--katex-asset "auto-render.min.js") "\n</script>\n"
          "<script>renderMathInElement(document.body,"
          "{throwOnError:false,errorColor:\"#B4232C\"});</script>\n"))

(defun org-ppt--math-source (value)
  "Split a LaTeX fragment VALUE into its source and whether it is display math.
Returns a cons of the delimiter-free source and the display flag."
  (let ((body "\\(\\(?:.\\|\n\\)*\\)"))
    (cond
     ((string-match (concat "\\`\\$\\$" body "\\$\\$\\'") value)
      (cons (match-string 1 value) t))
     ((string-match (concat "\\`\\\\\\[" body "\\\\\\]\\'") value)
      (cons (match-string 1 value) t))
     ((string-match (concat "\\`\\\\(" body "\\\\)\\'") value)
      (cons (match-string 1 value) nil))
     ((string-match (concat "\\`\\$" body "\\$\\'") value)
      (cons (match-string 1 value) nil))
     (t (cons value nil)))))

(defun org-ppt--math-placeholder (tex display fallback)
  "Queue TEX for rendering and return the marker standing in for it.
DISPLAY says whether it is display math and FALLBACK is what to emit if
the render never happens.  The whole deck's math goes to KaTeX in one
call at the end, so the marker is what the body carries until then."
  (push (list tex display fallback) org-ppt--math-queue)
  (format "<!--org-ppt-math:%d-->" (1- (length org-ppt--math-queue))))

(defun org-ppt--render-math-queue ()
  "Render the queued math with Node, newest-first order reversed.
Returns the list of HTML strings, or nil when Node or KaTeX could not
produce one for every entry — in which case the caller ships the runtime."
  (let* ((items (reverse org-ppt--math-queue))
         (script (expand-file-name "render.js" (org-ppt--katex-directory)))
         (payload (json-encode
                   `((items . ,(mapcar (lambda (entry)
                                         `((tex . ,(nth 0 entry))
                                           (display . ,(if (nth 1 entry) t :json-false))))
                                       items))))))
    (when (file-readable-p script)
      (with-temp-buffer
        (let ((status (condition-case err
                          (call-process-region payload nil org-ppt-node-program
                                               nil t nil script)
                        (error (message "org-ppt: %s" (error-message-string err))
                               nil))))
          (when (eq status 0)
            (let* ((reply (ignore-errors
                            (json-read-from-string (buffer-string))))
                   (error-text (cdr (assq 'error reply)))
                   (html (append (cdr (assq 'html reply)) nil)))
              (cond (error-text (message "org-ppt: KaTeX: %s" error-text) nil)
                    ((= (length html) (length items)) html)
                    (t nil)))))))))

(defun org-ppt--substitute-math (contents html)
  "Replace the math markers in CONTENTS with HTML, or with their fallbacks.
HTML is nil when pre-rendering failed, which puts the original delimiters
back so the shipped runtime can typeset them in the browser instead."
  (let ((entries (reverse org-ppt--math-queue)))
    (replace-regexp-in-string
     "<!--org-ppt-math:\\([0-9]+\\)-->"
     (lambda (marker)
       (let ((n (string-to-number (match-string 1 marker))))
         (or (nth n html) (nth 2 (nth n entries)) "")))
     contents t t)))

(defun org-ppt--katex-p (info)
  "Return non-nil when this deck needs the bundled KaTeX runtime.
INFO is the export communication channel.  Requires that KaTeX is the
resolved mode, that the document actually contained math, and that Org
was left in pass-through mode by `#+OPTIONS: tex:'."
  (and (eq org-ppt--math-mode 'katex)
       org-ppt--math-seen
       (eq (plist-get info :with-latex) 'mathjax)))

;;;; Data URIs

(defconst org-ppt--mime-types
  '(("png" . "image/png") ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg")
    ("gif" . "image/gif") ("svg" . "image/svg+xml") ("webp" . "image/webp")
    ("avif" . "image/avif") ("bmp" . "image/bmp") ("ico" . "image/x-icon")
    ("tif" . "image/tiff") ("tiff" . "image/tiff") ("pdf" . "application/pdf"))
  "Extension to MIME type mapping for embedded assets.")

(defun org-ppt--mime-type (path)
  "Return a MIME type for PATH, or nil when the extension is unknown."
  (let ((ext (downcase (or (file-name-extension path) ""))))
    (cdr (assoc ext org-ppt--mime-types))))

(defun org-ppt--resolve-path (path info)
  "Expand PATH relative to the exported document described by INFO."
  (let* ((input (plist-get info :input-file))
         (base (if input (file-name-directory input) default-directory)))
    (expand-file-name (org-ppt--strip-file-prefix path) base)))

(defun org-ppt--strip-file-prefix (path)
  "Remove a leading `file:' or `file://' scheme from PATH."
  (cond
   ((string-prefix-p "file://" path) (substring path 7))
   ((string-prefix-p "file:" path) (substring path 5))
   (t path)))

(defun org-ppt--data-uri (path info)
  "Return PATH as a base64 data URI, or nil when it cannot be embedded."
  (let* ((full (org-ppt--resolve-path path info))
         (mime (org-ppt--mime-type full)))
    (when (and mime (file-readable-p full) (not (file-directory-p full)))
      (let ((size (file-attribute-size (file-attributes full))))
        (when (and size (> size org-ppt-embed-size-limit))
          (message "org-ppt: %s is %.1f MB; consider shrinking it"
                   (file-name-nondirectory full) (/ size 1048576.0))))
      (concat "data:" mime ";base64,"
              (base64-encode-string
               (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (insert-file-contents-literally full)
                 (buffer-string))
               t)))))

(defun org-ppt--embed-sources (html info)
  "Rewrite local src=\"…\" URLs in HTML into data URIs."
  (if (or (not (plist-get info :ppt-embed-images))
          ;; Most fragments carry no image at all; skip the scan entirely
          ;; rather than walking every already-embedded base64 blob.
          (not (string-match-p "src=\"" html)))
      html
    (replace-regexp-in-string
     "\\(<img\\|<source\\|<embed\\)\\([^>]*?\\)\\bsrc=\"\\([^\"]+\\)\""
     (lambda (m)
       ;; Read every group before doing work: `org-ppt--data-uri' matches on
       ;; the path, and the caller splices on the match data it would leave
       ;; behind.
       (let ((prefix (match-string 1 m))
             (middle (match-string 2 m))
             (url (match-string 3 m)))
         (if (string-match-p "\\`\\(data:\\|https?:\\|//\\)" url)
             m
           (let ((uri (save-match-data (org-ppt--data-uri url info))))
             (if uri
                 (concat prefix middle "src=\"" uri "\"")
               m)))))
     html t t)))

;;;; Small helpers

(defun org-ppt--parent (element)
  "Return the parent of ELEMENT, across Org versions."
  (if (fboundp 'org-element-parent)
      (org-element-parent element)
    (org-element-property :parent element)))

(defun org-ppt--strip-tags (html)
  "Remove HTML tags from HTML, leaving escaped text."
  (string-trim (replace-regexp-in-string "<[^>]*>" "" (or html ""))))

(defun org-ppt--slide-level (info)
  "Return the outline level that becomes a slide, per INFO."
  (let ((raw (plist-get info :ppt-slide-level)))
    (max 1 (cond ((integerp raw) raw)
                 ((and (stringp raw) (string-match-p "\\`[0-9]+\\'" raw))
                  (string-to-number raw))
                 (t 1)))))

(defun org-ppt--stage-geometry (info)
  "Return (WIDTH HEIGHT ASPECT) for the configured aspect ratio in INFO."
  (if (equal (plist-get info :ppt-aspect) "4:3")
      (list 1024 768 "4 / 3")
    (list 1280 720 "16 / 9")))

(defun org-ppt--split-off-slides (contents)
  "Split CONTENTS at the first nested slide.
Returns a cons of the text before any child slide and the rest.  The
exporter emits every slide as a top-level <section>, so this is how a
parent headline keeps its own prose while its children stay siblings."
  (let ((pos (string-match "<section class=\"opp-slide" (or contents ""))))
    (if pos
        (cons (substring contents 0 pos) (substring contents pos))
      (cons (or contents "") ""))))

(defun org-ppt--extract-notes (contents)
  "Pull <aside class=\"opp-notes\"> blocks out of CONTENTS.
Returns a cons of the cleaned body and the concatenated notes."
  (let ((body contents) (notes "") (case-fold-search t))
    (while (string-match
            "<aside class=\"opp-notes\">\\(\\(?:.\\|\n\\)*?\\)</aside>" body)
      (setq notes (concat notes (match-string 1 body)))
      (setq body (replace-match "" t t body)))
    (cons body notes)))

;;;; Translators

(defun org-ppt-section (_section contents _info)
  "Return CONTENTS unchanged; slides supply their own containers."
  (or contents ""))

(defun org-ppt--slide (title body notes classes data-title)
  "Assemble one slide from TITLE, BODY, NOTES, CLASSES and DATA-TITLE."
  (concat
   (format "<section class=\"opp-slide%s\" data-title=\"%s\">\n"
           (if (string-empty-p classes) "" (concat " " classes))
           (or data-title ""))
   (when (and title (not (string-empty-p title)))
     (format "<h2>%s</h2>\n" title))
   (format "<div class=\"opp-body\">\n%s</div>\n" (or body ""))
   (unless (string-empty-p (string-trim (or notes "")))
     (format "<aside class=\"opp-notes\">%s</aside>\n" notes))
   "</section>\n"))

(defun org-ppt--divider (title body classes data-title)
  "Assemble a full-bleed section divider from TITLE, BODY and CLASSES."
  (concat
   (format "<section class=\"opp-slide opp-section%s\" data-title=\"%s\">\n"
           (if (string-empty-p classes) "" (concat " " classes))
           (or data-title ""))
   (format "<h2>%s</h2>\n" title)
   (if (string-empty-p (string-trim (or body "")))
       ""
     (format "<div class=\"opp-body\">\n%s</div>\n" body))
   "</section>\n"))

(defun org-ppt-headline (headline contents info)
  "Transcode HEADLINE into a slide, a divider, or an in-slide heading."
  (unless (org-element-property :footnote-section-p headline)
    (let* ((level (org-export-get-relative-level headline info))
           (slide-level (org-ppt--slide-level info))
           (tags (org-export-get-tags headline info))
           (title (org-export-data (org-element-property :title headline) info))
           (data-title (org-ppt--strip-tags title))
           (extra (or (org-element-property :PPT_CLASS headline) ""))
           (contents (or contents "")))
      (cond
       ;; A subtree tagged :notes: never reaches the audience.
       ((member "notes" tags)
        (format "<aside class=\"opp-notes\">%s</aside>" contents))

       ;; Above the slide level, or explicitly tagged, this is a divider.
       ((or (< level slide-level) (member "section" tags))
        (let* ((split (org-ppt--split-off-slides contents))
               (intro (car split))
               (children (cdr split)))
          (concat (org-ppt--divider title intro extra data-title) children)))

       ;; At the slide level: a slide.
       ((= level slide-level)
        (let* ((split (org-ppt--extract-notes contents))
               (classes (string-join
                         (delq nil (list (unless (string-empty-p extra) extra)
                                         (when (member "figure" tags) "opp-figure")
                                         (when (member "center" tags) "opp-center")))
                         " ")))
          (org-ppt--slide title (car split) (cdr split) classes data-title)))

       ;; Below the slide level: an ordinary heading inside the slide.
       (t
        (let ((tag (if (= level (1+ slide-level)) "h3" "h4")))
          (format "<%s>%s</%s>\n%s" tag title tag contents)))))))

(defun org-ppt-link (link desc info)
  "Transcode LINK with DESC, embedding local images as data URIs."
  (org-ppt--embed-sources (org-html-link link desc info) info))

(defun org-ppt-paragraph (paragraph contents info)
  "Transcode PARAGRAPH, embedding any images it wraps."
  (org-ppt--embed-sources (org-html-paragraph paragraph contents info) info))

(defun org-ppt--prerendering-p (info)
  "Return non-nil when math in this export is typeset at export time.
INFO is the export communication channel; `#+OPTIONS: tex:nil' still wins."
  (and org-ppt--math-prerender (plist-get info :with-latex)))

(defun org-ppt-latex-fragment (fragment _contents info)
  "Transcode a LaTeX FRAGMENT, embedding the image it renders to."
  (setq org-ppt--math-seen t)
  (if (org-ppt--prerendering-p info)
      (let* ((source (org-ppt--math-source
                      (org-element-property :value fragment)))
             (tex (car source))
             (display (cdr source)))
        (org-ppt--math-placeholder
         tex display (format (if display "\\[%s\\]" "\\(%s\\)") tex)))
    (org-ppt--embed-sources (org-html-latex-fragment fragment nil info) info)))

(defun org-ppt-latex-environment (environment _contents info)
  "Transcode a LaTeX ENVIRONMENT, embedding the image it renders to."
  (setq org-ppt--math-seen t)
  (if (org-ppt--prerendering-p info)
      ;; KaTeX reads \begin{…}…\end{…} directly, so the environment is its
      ;; own source and its own fallback.
      (let ((value (org-element-property :value environment)))
        (org-ppt--math-placeholder value t value))
    (org-ppt--embed-sources (org-html-latex-environment environment nil info) info)))

(defun org-ppt--fragment-list-p (element info)
  "Non-nil when ELEMENT is a plain list that should be revealed stepwise."
  (and (eq (org-element-type element) 'plain-list)
       (let ((attr (org-export-read-attribute :attr_ppt element)))
         (if (plist-member attr :fragment)
             (let ((v (plist-get attr :fragment)))
               (not (member v '(nil "nil" "no" "off"))))
           (plist-get info :ppt-fragment-lists)))))

(defun org-ppt-item (item contents info)
  "Transcode ITEM, adding the fragment class when its list asks for it."
  (let ((html (org-html-item item contents info)))
    (if (not (org-ppt--fragment-list-p (org-ppt--parent item) info))
        html
      (cond
       ((string-match "\\`\\([ \t\n]*\\)<li class=\"" html)
        (replace-match "\\1<li class=\"fragment " t nil html))
       ((string-match "\\`\\([ \t\n]*\\)<li\\([ >]\\)" html)
        (replace-match "\\1<li class=\"fragment\"\\2" t nil html))
       (t html)))))

(defconst org-ppt--special-blocks
  '(("notes"    . "<aside class=\"opp-notes\">%s</aside>")
    ("columns"  . "<div class=\"opp-columns\">%s</div>")
    ("column"   . "<div class=\"opp-column\">%s</div>")
    ("note"     . "<div class=\"opp-callout\">%s</div>")
    ("callout"  . "<div class=\"opp-callout\">%s</div>")
    ("warning"  . "<div class=\"opp-callout opp-warning\">%s</div>")
    ("fragment" . "<div class=\"fragment\">%s</div>")
    ("center"   . "<div class=\"opp-center\">%s</div>")
    ("big"      . "<div class=\"opp-big\">%s</div>"))
  "Special block names org-ppt understands, and their HTML shape.")

(defun org-ppt-special-block (block contents info)
  "Transcode a presentation-specific BLOCK, else defer to ox-html."
  (let* ((type (downcase (or (org-element-property :type block) "")))
         (shape (cdr (assoc type org-ppt--special-blocks))))
    (if shape
        (format shape (or contents ""))
      (org-html-special-block block contents info))))

;;;; Generated slides

(defun org-ppt--title-slide (info)
  "Build the opening slide from the document metadata in INFO."
  (when (plist-get info :ppt-title-slide)
    (let* ((title (org-export-data (plist-get info :title) info))
           (subtitle (org-export-data (plist-get info :subtitle) info))
           (author (and (plist-get info :with-author)
                        (org-export-data (plist-get info :author) info)))
           (email (and (plist-get info :with-email)
                       (org-export-data (plist-get info :email) info)))
           (date (and (plist-get info :with-date)
                      (org-export-data (org-export-get-date info) info)))
           (meta (string-join
                  (delq nil
                        (list (unless (string-empty-p (or author ""))
                                (format "<span class=\"opp-author\">%s</span>" author))
                              (unless (string-empty-p (or email ""))
                                email)
                              (unless (string-empty-p (or date ""))
                                date)))
                  "<br>")))
      (unless (string-empty-p (string-trim (or title "")))
        (concat
         (format "<section class=\"opp-slide opp-title\" data-title=\"%s\">\n"
                 (org-ppt--strip-tags title))
         (format "<h1>%s</h1>\n" title)
         (unless (string-empty-p (or subtitle ""))
           (format "<p class=\"opp-subtitle\">%s</p>\n" subtitle))
         "<div class=\"opp-rule\"></div>\n"
         (unless (string-empty-p meta)
           (format "<div class=\"opp-meta\">%s</div>\n" meta))
         "</section>\n")))))

(defun org-ppt--outline-slide (info)
  "Build an agenda slide listing the top-level sections described by INFO."
  (when (plist-get info :with-toc)
    (let* ((slide-level (org-ppt--slide-level info))
           ;; With section dividers in play the agenda lists the sections;
           ;; a flat deck lists its slides.
           (depth (max 1 (1- slide-level)))
           (items
            (delq nil
                  (org-element-map (plist-get info :parse-tree) 'headline
                    (lambda (h)
                      (when (and (= (org-export-get-relative-level h info) depth)
                                 (not (member "notes" (org-export-get-tags h info)))
                                 (not (org-element-property :footnote-section-p h)))
                        (format "<li>%s</li>"
                                (org-export-data
                                 (org-element-property :title h) info))))
                    info))))
      (when items
        (org-ppt--slide
         org-ppt-toc-title
         (format "<ul>\n%s\n</ul>" (string-join items "\n"))
         "" "" org-ppt-toc-title)))))

;;;; Document assembly

(defun org-ppt-inner-template (contents info)
  "Wrap CONTENTS, the transcoded slides, in the presentation stage."
  (pcase-let ((`(,w ,h ,ar) (org-ppt--stage-geometry info)))
    (concat
     "<div class=\"opp-viewport\">\n"
     (format (concat "<div class=\"opp-stage\" data-transition=\"%s\" "
                     "style=\"--stage-w:%dpx;--stage-h:%dpx;--stage-ar:%s\">\n")
             (or (plist-get info :ppt-transition) "fade") w h ar)
     (or (org-ppt--title-slide info) "")
     (or (org-ppt--outline-slide info) "")
     contents
     "</div>\n</div>\n")))

(defun org-ppt--chrome-template (info)
  "Return the per-slide footer template described by INFO."
  (let* ((footer (or (plist-get info :ppt-footer) ""))
         (logo (plist-get info :ppt-logo))
         (logo-uri (and logo (org-ppt--data-uri logo info))))
    (concat
     "<template id=\"opp-chrome-template\"><div class=\"opp-chrome\">"
     (format "<span class=\"opp-footer\">%s</span>"
             (org-html-encode-plain-text footer))
     (if logo-uri (format "<img class=\"opp-logo\" src=\"%s\" alt=\"\">" logo-uri) "")
     "<span class=\"opp-slideno\"></span>"
     "</div></template>\n")))

(defun org-ppt--accent-style (info)
  "Return a <style> block overriding the accent colour, per INFO."
  (let ((accent (plist-get info :ppt-accent)))
    (if (and accent (not (string-empty-p accent)))
        (format "<style>:root,:root[data-theme=\"dark\"]{--accent:%s}</style>\n"
                accent)
      "")))

(defun org-ppt-template (contents info)
  "Return the complete, self-contained HTML document around CONTENTS."
  (let* ((rendered (and org-ppt--math-queue (org-ppt--render-math-queue)))
         (contents (if org-ppt--math-queue
                       (org-ppt--substitute-math contents rendered)
                     contents))
         ;; Pre-rendered math needs the stylesheet but no runtime, and only
         ;; the faces it actually reached for.  Everything else that carries
         ;; math needs the runtime and, not knowing what it will draw, the
         ;; whole family set.
         (families (and rendered (org-ppt--katex-families-used contents)))
         (runtime (and (not rendered) (org-ppt--katex-p info)))
         (styled (or rendered runtime))
         (title (org-export-data (plist-get info :title) info))
         (theme (if (equal (plist-get info :ppt-theme) "dark") "dark" "light"))
         (lang (or (plist-get info :language) "en"))
         (author (org-export-data (plist-get info :author) info)))
    (concat
     "<!DOCTYPE html>\n"
     (format "<html lang=\"%s\" data-theme=\"%s\">\n" lang theme)
     "<head>\n"
     "<meta charset=\"utf-8\">\n"
     "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
     (format "<meta name=\"generator\" content=\"org-ppt %s\">\n" (org-ppt-version))
     (if (string-empty-p (or author ""))
         ""
       (format "<meta name=\"author\" content=\"%s\">\n"
               (org-html-encode-plain-text author)))
     (format "<title>%s</title>\n"
             (if (string-empty-p (org-ppt--strip-tags title))
                 "Presentation"
               (org-ppt--strip-tags title)))
     "<style>\n" (org-ppt--asset "org-ppt.css") "\n</style>\n"
     (if styled
         (concat "<style>\n" (org-ppt--katex-css families) "\n</style>\n")
       "")
     (org-ppt--accent-style info)
     "</head>\n<body>\n"
     contents
     (org-ppt--chrome-template info)
     (if runtime (org-ppt--katex-scripts) "")
     "<script>\n" (org-ppt--asset "org-ppt.js") "\n</script>\n"
     "</body>\n</html>\n")))

;;;; Backend

(org-export-define-derived-backend 'ppt 'html
  :menu-entry
  '(?s "Export to presentation slides"
       ((?s "As HTML file" org-ppt-export-to-html)
        (?o "As HTML file and open" org-ppt-export-to-html-and-open)
        (?b "As buffer" org-ppt-export-as-html)))
  :options-alist
  '((:ppt-theme "ORG_PPT_THEME" nil org-ppt-theme t)
    (:ppt-accent "ORG_PPT_ACCENT" nil org-ppt-accent t)
    (:ppt-aspect "ORG_PPT_ASPECT" nil org-ppt-aspect t)
    (:ppt-transition "ORG_PPT_TRANSITION" nil org-ppt-transition t)
    (:ppt-footer "ORG_PPT_FOOTER" nil org-ppt-footer t)
    (:ppt-logo "ORG_PPT_LOGO" nil org-ppt-logo t)
    (:ppt-slide-level "ORG_PPT_SLIDE_LEVEL" nil org-ppt-slide-level t)
    (:ppt-embed-images nil "ppt-embed" org-ppt-embed-images)
    (:ppt-title-slide nil "ppt-title" org-ppt-title-slide)
    (:ppt-fragment-lists nil "ppt-frag" org-ppt-fragment-lists)
    ;; Org defaults `toc' to t. A deck should not grow an agenda slide
    ;; nobody asked for, so opt in with #+OPTIONS: toc:t.
    (:with-toc nil "toc" nil)
    ;; A deck is self-contained, so no external stylesheet or script.
    (:html-head-include-default-style nil "html-style" nil)
    (:html-head-include-scripts nil "html-scripts" nil)
    (:with-latex nil "tex" org-ppt-with-latex))
  :translate-alist
  '((template . org-ppt-template)
    (inner-template . org-ppt-inner-template)
    (headline . org-ppt-headline)
    (section . org-ppt-section)
    (link . org-ppt-link)
    (paragraph . org-ppt-paragraph)
    (latex-fragment . org-ppt-latex-fragment)
    (latex-environment . org-ppt-latex-environment)
    (item . org-ppt-item)
    (special-block . org-ppt-special-block)))

;;;; Export commands

(defun org-ppt--latex-programs (process)
  "Return the programs Org declares for PROCESS, or nil when it knows none."
  (plist-get (cdr (assq process org-preview-latex-process-alist)) :programs))

(defun org-ppt--missing-latex-program (process)
  "Return the first program PROCESS needs that is not on PATH."
  (seq-find (lambda (program) (not (executable-find program)))
            (org-ppt--latex-programs process)))

(defun org-ppt--resolved-latex ()
  "Return `org-ppt-with-latex', downgraded when its toolchain is incomplete.
Every image-rendering process needs more than one binary — `dvipng' also
needs dvipng, `imagemagick' also needs convert — so the whole program
list Org declares is probed, and the one that is absent is named."
  (let ((mode org-ppt-with-latex))
    (if (not (assq mode org-preview-latex-process-alist))
        mode
      (let ((missing (org-ppt--missing-latex-program mode)))
        (if (not missing)
            mode
          (message "org-ppt: %s needs `%s', which is not installed; \
rendering math with the bundled KaTeX instead" mode missing)
          'katex)))))

(defmacro org-ppt--with-export-settings (&rest body)
  "Run BODY with the HTML settings a self-contained deck requires."
  (declare (indent 0) (debug t))
  `(let* ((org-html-htmlize-output-type 'css)
          (org-html-head-include-default-style nil)
          (org-html-head-include-scripts nil)
          (org-html-validation-link nil)
          (org-html-doctype "html5")
          (org-html-html5-fancy t)
          (org-html-container-element "div")
          (org-html-self-link-headlines nil)
          (org-ppt--math-seen nil)
          (org-ppt--math-queue nil)
          (org-ppt--math-mode (org-ppt--resolved-latex))
          (org-ppt--math-prerender (and (eq org-ppt--math-mode 'katex)
                                        (executable-find org-ppt-node-program)
                                        t))
          ;; KaTeX consumes the same pass-through Org emits for MathJax:
          ;; \(…\) and raw \begin{…} environments, which are already the
          ;; delimiters auto-render looks for.  No CDN reaches the deck
          ;; because `org-ppt-template' replaces `org-html-template'.
          (org-ppt-with-latex (if (eq org-ppt--math-mode 'katex)
                                  'mathjax
                                org-ppt--math-mode)))
     ,@body))

;;;###autoload
(defun org-ppt-export-as-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export the current buffer as a presentation to a scratch buffer.
ASYNC, SUBTREEP, VISIBLE-ONLY, BODY-ONLY and EXT-PLIST are as in
`org-export-to-buffer'."
  (interactive)
  (org-ppt--with-export-settings
    (org-export-to-buffer 'ppt "*Org PPT Export*"
      async subtreep visible-only body-only ext-plist
      (lambda () (set-auto-mode t)))))

;;;###autoload
(defun org-ppt-export-to-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export the current buffer to a self-contained presentation HTML file.
Returns the file name.  ASYNC, SUBTREEP, VISIBLE-ONLY, BODY-ONLY and
EXT-PLIST are as in `org-export-to-file'."
  (interactive)
  (let ((file (expand-file-name (org-export-output-file-name ".html" subtreep))))
    (org-ppt--with-export-settings
      (org-export-to-file 'ppt file
        async subtreep visible-only body-only ext-plist))))

;;;###autoload
(defun org-ppt-export-to-html-and-open (&optional async subtreep visible-only)
  "Export the current buffer to a presentation and open it in a browser.
ASYNC, SUBTREEP and VISIBLE-ONLY are as in `org-ppt-export-to-html'."
  (interactive)
  (let ((file (org-ppt-export-to-html async subtreep visible-only)))
    (when (stringp file)
      (funcall org-ppt-browser-function (concat "file://" (expand-file-name file))))
    file))

;;;###autoload
(defun org-ppt-export-to-html-file (org-file &optional html-file)
  "Export ORG-FILE to HTML-FILE non-interactively.
Handy from a Makefile: emacs -Q --batch -l org-ppt.el \\
  --eval \\='(org-ppt-export-to-html-file \"talk.org\")\\='."
  (let ((buf (find-file-noselect org-file)))
    (unwind-protect
        (with-current-buffer buf
          (let ((out (org-ppt-export-to-html)))
            (when (and html-file (not (equal out html-file)))
              (rename-file out html-file t)
              (setq out html-file))
            out))
      (kill-buffer buf))))

(provide 'org-ppt)

;;; org-ppt.el ends here
