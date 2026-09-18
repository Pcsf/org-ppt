# org-ppt --- build, test and preview
#
# The package itself needs no build step: assets/ is read and inlined at
# export time. Byte-compiling is only a correctness check.

EMACS    ?= emacs
CHROMIUM ?= chromium
BATCH     = $(EMACS) -Q --batch -L .

BUILD    = build
DEMO_ORG = examples/demo.org
DEMO_HTML= examples/demo.html
DEMO_PDF = $(BUILD)/demo.pdf

.PHONY: all compile test demo pdf verify clean

all: compile

compile:
	$(BATCH) -f batch-byte-compile org-ppt.el

test: compile
	$(BATCH) -l test/org-ppt-test.el -f ert-run-tests-batch-and-exit

demo:
	$(BATCH) -l org-ppt --eval '(org-ppt-export-to-html-file "$(DEMO_ORG)")'
	@echo "wrote $(DEMO_HTML)"

pdf: demo | $(BUILD)
	$(CHROMIUM) --headless --disable-gpu --no-sandbox \
	  --print-to-pdf=$(DEMO_PDF) --no-pdf-header-footer \
	  --virtual-time-budget=6000 "file://$(CURDIR)/$(DEMO_HTML)"
	@echo "wrote $(DEMO_PDF)"

# Renders a few slides headless, so a design change can be eyeballed without
# opening a browser by hand. The list covers one slide per feature: 1 title
# background from a template, 9 code, 11 math, 12 headings inside columns,
# 20 a slide autofit shrank, 21 one it left alone, 22 one sized by hand.
#
# --force-prefers-reduced-motion is load-bearing, not tidiness: without it the
# capture races the 0.28s entrance fade and two runs of the same page differ
# by more than a percent of their pixels for no reason in the code.
VERIFY_SLIDES ?= 1 9 11 12 20 21 22
verify: demo | $(BUILD)
	@for n in $(VERIFY_SLIDES); do \
	  $(CHROMIUM) --headless --disable-gpu --no-sandbox --hide-scrollbars \
	    --window-size=1600,900 --force-prefers-reduced-motion \
	    --virtual-time-budget=8000 \
	    --screenshot=$(BUILD)/slide-$$n.png \
	    "file://$(CURDIR)/$(DEMO_HTML)#/$$n" 2>/dev/null; \
	done
	@echo "screenshots in $(BUILD)/"

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f *.elc test/*.elc $(DEMO_HTML)
	rm -rf $(BUILD)
