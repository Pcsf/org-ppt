/* org-ppt.js --- presentation runtime for org-ppt
 *
 * No dependencies, no network. Everything the deck needs is in this file and
 * the inlined stylesheet, so the exported .html works from file:// forever.
 */
(function () {
  "use strict";

  var doc = document;
  var root = doc.documentElement;

  function $(sel, ctx) { return (ctx || doc).querySelector(sel); }
  function $$(sel, ctx) { return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel)); }

  var stage = $(".opp-stage");
  if (!stage) { return; }

  var viewport = $(".opp-viewport");
  var slides = $$(".opp-slide", stage);
  if (!slides.length) { return; }

  var state = {
    index: 0,
    step: 0,          // how many fragments of the current slide are revealed
    overview: false,
    blackout: false,
    speaker: false,
    help: false,
    startedAt: null,
    paused: true,
    elapsed: 0,
    keyBuffer: ""
  };

  /* ------------------------------------------------------------ scaffolding */

  var chromeTpl = $("#opp-chrome-template");

  slides.forEach(function (slide, i) {
    slide.dataset.n = String(i + 1);
    slide.setAttribute("aria-hidden", "true");

    var progress = doc.createElement("div");
    progress.className = "opp-progress";
    slide.appendChild(progress);

    if (chromeTpl && !slide.classList.contains("opp-title")) {
      var chrome = chromeTpl.content.firstElementChild.cloneNode(true);
      $(".opp-slideno", chrome).textContent = (i + 1) + " / " + slides.length;
      slide.appendChild(chrome);
    }
  });

  function fragmentsOf(slide) {
    // Fragments nested inside a deeper fragment are stepped by their own turn,
    // so a flat document-order list is exactly right.
    return $$(".fragment", slide);
  }

  /* ----------------------------------------------------------------- layout */

  function rescale() {
    if (state.overview) { return; }
    var w = stage.offsetWidth || 1280;
    var h = stage.offsetHeight || 720;
    var pad = doc.fullscreenElement ? 0 : 28;
    var s = Math.min((window.innerWidth - pad) / w, (window.innerHeight - pad) / h);
    stage.style.setProperty("--scale", String(s));
  }

  /* -------------------------------------------------------------- rendering */

  function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }

  function render(backwards) {
    state.index = clamp(state.index, 0, slides.length - 1);
    var slide = slides[state.index];
    var frags = fragmentsOf(slide);
    state.step = clamp(state.step, 0, frags.length);

    slides.forEach(function (s) {
      var current = s === slide;
      s.classList.toggle("is-current", current);
      s.classList.toggle("is-backwards", current && !!backwards);
      s.setAttribute("aria-hidden", current ? "false" : "true");
    });

    frags.forEach(function (f, i) { f.classList.toggle("is-visible", i < state.step); });

    var pct = slides.length > 1 ? (state.index / (slides.length - 1)) * 100 : 100;
    var bar = $(".opp-progress", slide);
    if (bar) { bar.style.width = pct + "%"; }

    doc.title = (slide.dataset.title || "").trim() || baseTitle;
    updateSpeaker();
    writeHash();
  }

  var baseTitle = doc.title;

  /* ------------------------------------------------------------- navigation */

  function next() {
    var frags = fragmentsOf(slides[state.index]);
    if (state.step < frags.length) { state.step++; render(false); return; }
    if (state.index < slides.length - 1) { state.index++; state.step = 0; render(false); }
  }

  function prev() {
    if (state.step > 0) { state.step--; render(true); return; }
    if (state.index > 0) {
      state.index--;
      // Entering a slide backwards shows it fully built, as in PowerPoint.
      state.step = fragmentsOf(slides[state.index]).length;
      render(true);
    }
  }

  function nextSlide() {
    if (state.index < slides.length - 1) { state.index++; state.step = 0; render(false); }
  }
  function prevSlide() {
    if (state.index > 0) { state.index--; state.step = 0; render(true); }
  }

  function goTo(i, step) {
    var back = i < state.index;
    state.index = clamp(i, 0, slides.length - 1);
    state.step = step === undefined ? 0 : step;
    render(back);
  }

  /* -------------------------------------------------------------- deep link */

  var suppressHash = false;

  function writeHash() {
    suppressHash = true;
    var h = "#/" + (state.index + 1) + (state.step ? "/" + state.step : "");
    if (location.hash !== h) {
      try { history.replaceState(null, "", h); }
      catch (e) { location.hash = h; }   // file:// in some browsers
    }
    setTimeout(function () { suppressHash = false; }, 0);
  }

  function readHash() {
    var m = /^#\/(\d+)(?:\/(\d+))?/.exec(location.hash || "");
    if (!m) { return false; }
    goTo(parseInt(m[1], 10) - 1, m[2] ? parseInt(m[2], 10) : 0);
    return true;
  }

  window.addEventListener("hashchange", function () {
    if (!suppressHash) { readHash(); }
  });

  /* --------------------------------------------------------------- overview */

  var ovLayer = doc.createElement("div");
  ovLayer.className = "opp-overview-layer";
  ovLayer.innerHTML = '<div class="opp-ov-grid"></div>';
  doc.body.appendChild(ovLayer);

  function buildOverview() {
    var grid = $(".opp-ov-grid", ovLayer);
    grid.textContent = "";
    slides.forEach(function (slide, i) {
      var thumb = doc.createElement("div");
      thumb.className = "opp-thumb" + (i === state.index ? " is-current" : "");
      thumb.dataset.index = String(i);

      var inner = doc.createElement("div");
      inner.className = "opp-thumb-inner";
      inner.appendChild(slide.cloneNode(true));

      var badge = doc.createElement("span");
      badge.className = "opp-thumb-badge";
      badge.textContent = String(i + 1);

      thumb.appendChild(inner);
      thumb.appendChild(badge);
      grid.appendChild(thumb);
    });
    scaleThumbs();
  }

  function scaleThumbs() {
    var w = stage.offsetWidth || 1280;
    $$(".opp-thumb", ovLayer).forEach(function (thumb) {
      var inner = $(".opp-thumb-inner", thumb);
      if (inner) { inner.style.transform = "scale(" + (thumb.clientWidth / w) + ")"; }
    });
  }

  function setOverview(on) {
    state.overview = on;
    if (on) { buildOverview(); }
    ovLayer.classList.toggle("is-open", on);
    if (!on) { rescale(); }
  }

  ovLayer.addEventListener("click", function (ev) {
    var thumb = ev.target.closest(".opp-thumb");
    if (!thumb) { return; }
    setOverview(false);
    goTo(parseInt(thumb.dataset.index, 10), 0);
  });

  /* ---------------------------------------------------------- speaker notes */

  var speaker = doc.createElement("div");
  speaker.className = "opp-speaker";
  speaker.innerHTML =
    '<header><span class="opp-timer">00:00</span>' +
    '<button class="opp-sp-btn" data-act="toggle">Start</button>' +
    '<button class="opp-sp-btn" data-act="reset">Reset</button></header>' +
    '<div class="opp-sp-body"></div>' +
    '<div class="opp-sp-next"></div>';
  doc.body.appendChild(speaker);

  function updateSpeaker() {
    if (!state.speaker) { return; }
    var slide = slides[state.index];
    var notes = $(".opp-notes", slide);
    var body = $(".opp-sp-body", speaker);
    if (notes && notes.innerHTML.trim()) {
      body.innerHTML = notes.innerHTML;
    } else {
      body.innerHTML = '<p class="opp-sp-empty">No notes on this slide.</p>';
    }
    var nxt = slides[state.index + 1];
    $(".opp-sp-next", speaker).innerHTML = nxt
      ? "Next: <b>" + escapeHtml(nxt.dataset.title || "slide " + (state.index + 2)) + "</b>"
      : "<b>Last slide.</b>";
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  function tick() {
    if (!state.paused && state.startedAt !== null) {
      state.elapsed = Date.now() - state.startedAt;
    }
    var total = Math.floor(state.elapsed / 1000);
    var t = $(".opp-timer", speaker);
    if (t) {
      t.textContent = (total >= 3600 ? pad2(Math.floor(total / 3600)) + ":" : "") +
        pad2(Math.floor(total / 60) % 60) + ":" + pad2(total % 60);
    }
  }
  setInterval(tick, 250);

  speaker.addEventListener("click", function (ev) {
    var act = ev.target.dataset && ev.target.dataset.act;
    if (act === "toggle") {
      if (state.paused) {
        state.startedAt = Date.now() - state.elapsed;
        state.paused = false;
        ev.target.textContent = "Pause";
      } else {
        state.paused = true;
        ev.target.textContent = "Start";
      }
    } else if (act === "reset") {
      state.elapsed = 0;
      state.startedAt = Date.now();
      tick();
    }
  });

  function setSpeaker(on) {
    state.speaker = on;
    speaker.classList.toggle("is-open", on);
    if (on) {
      if (state.paused && state.elapsed === 0) {
        state.startedAt = Date.now();
        state.paused = false;
        var btn = $('[data-act="toggle"]', speaker);
        if (btn) { btn.textContent = "Pause"; }
      }
      updateSpeaker();
    }
  }

  /* ------------------------------------------------------------------- help */

  var help = doc.createElement("div");
  help.className = "opp-overlay";
  help.innerHTML =
    '<div class="opp-panel"><h2>Keyboard</h2><table><tbody>' +
    row("&rarr; &darr; Space PgDn / click", "Next step or slide") +
    row("&larr; &uarr; PgUp", "Previous step or slide") +
    row("N / P", "Next / previous slide, skipping steps") +
    row("Home / End", "First / last slide") +
    row("digits then Enter", "Jump to that slide number") +
    row("O or Esc", "Slide overview") +
    row("F", "Fullscreen") +
    row("S", "Speaker notes, with timer") +
    row("B or .", "Blank the screen") +
    row("D", "Light / dark theme") +
    row("Ctrl+P", "Print — one page per slide, save as PDF") +
    row("? or H", "This help") +
    "</tbody></table></div>";
  doc.body.appendChild(help);

  function row(k, v) {
    return "<tr><td><kbd>" + k + "</kbd></td><td>" + v + "</td></tr>";
  }

  function setHelp(on) { state.help = on; help.classList.toggle("is-open", on); }
  help.addEventListener("click", function () { setHelp(false); });

  /* ------------------------------------------------------------------ theme */

  function currentTheme() { return root.getAttribute("data-theme") === "dark" ? "dark" : "light"; }

  function setTheme(name) {
    root.setAttribute("data-theme", name);
    try { localStorage.setItem("org-ppt-theme", name); } catch (e) { /* private mode */ }
  }

  try {
    var saved = localStorage.getItem("org-ppt-theme");
    if (saved === "dark" || saved === "light") { root.setAttribute("data-theme", saved); }
  } catch (e) { /* ignore */ }

  /* --------------------------------------------------------------- blackout */

  function setBlackout(on) {
    state.blackout = on;
    doc.body.classList.toggle("opp-blackout", on);
  }

  /* ------------------------------------------------------------- fullscreen */

  function toggleFullscreen() {
    if (doc.fullscreenElement) {
      if (doc.exitFullscreen) { doc.exitFullscreen(); }
    } else if (doc.documentElement.requestFullscreen) {
      doc.documentElement.requestFullscreen().catch(function () { /* denied */ });
    }
  }

  doc.addEventListener("fullscreenchange", rescale);

  /* ---------------------------------------------------------------- keyboard */

  doc.addEventListener("keydown", function (ev) {
    if (ev.metaKey || ev.ctrlKey || ev.altKey) { return; }
    var tag = (ev.target.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea" || ev.target.isContentEditable) { return; }

    var k = ev.key;

    if (/^[0-9]$/.test(k)) {
      state.keyBuffer += k;
      return;   // digits only act once Enter confirms them
    }
    if (k === "Enter") {
      if (state.keyBuffer) {
        goTo(parseInt(state.keyBuffer, 10) - 1, 0);
        state.keyBuffer = "";
        ev.preventDefault();
      }
      return;
    }
    state.keyBuffer = "";

    switch (k) {
      case "ArrowRight": case "ArrowDown": case " ": case "PageDown":
        next(); break;
      case "ArrowLeft": case "ArrowUp": case "PageUp":
        prev(); break;
      case "n": case "N": nextSlide(); break;
      case "p": case "P": prevSlide(); break;
      case "Home": goTo(0, 0); break;
      case "End": goTo(slides.length - 1, 0); break;
      case "o": case "O": setOverview(!state.overview); break;
      case "Escape":
        if (state.help) { setHelp(false); }
        else if (state.blackout) { setBlackout(false); }
        else { setOverview(!state.overview); }
        break;
      case "f": case "F": toggleFullscreen(); break;
      case "s": case "S": setSpeaker(!state.speaker); break;
      case "b": case "B": case ".": setBlackout(!state.blackout); break;
      case "d": case "D": setTheme(currentTheme() === "dark" ? "light" : "dark"); break;
      case "?": case "h": case "H": setHelp(!state.help); break;
      default: return;
    }
    ev.preventDefault();
  });

  /* ------------------------------------------------------- pointer & touch */

  viewport.addEventListener("click", function (ev) {
    if (state.overview || state.help) { return; }
    // Never steal a click meant for content the audience is being shown.
    if (ev.target.closest("a, button, input, select, textarea, pre, table, .opp-speaker")) { return; }
    var sel = window.getSelection();
    if (sel && String(sel).length > 0) { return; }
    if (ev.clientX < window.innerWidth * 0.18) { prev(); } else { next(); }
  });

  var touchX = null, touchY = null;
  viewport.addEventListener("touchstart", function (ev) {
    if (ev.touches.length !== 1) { return; }
    touchX = ev.touches[0].clientX;
    touchY = ev.touches[0].clientY;
  }, { passive: true });

  viewport.addEventListener("touchend", function (ev) {
    if (touchX === null) { return; }
    var t = ev.changedTouches[0];
    var dx = t.clientX - touchX;
    var dy = t.clientY - touchY;
    touchX = touchY = null;
    if (Math.abs(dx) < 55 || Math.abs(dx) < Math.abs(dy)) { return; }
    if (dx < 0) { next(); } else { prev(); }
  }, { passive: true });

  /* ----------------------------------------------------------------- print */

  window.addEventListener("beforeprint", function () { doc.body.classList.add("opp-printing"); });
  window.addEventListener("afterprint", function () { doc.body.classList.remove("opp-printing"); });

  /* ------------------------------------------------------------------ boot */

  window.addEventListener("resize", function () {
    rescale();
    if (state.overview) { scaleThumbs(); }
  });

  rescale();
  if (!readHash()) { render(false); }

  // Fonts and images settle after first paint; re-measure once they have.
  window.addEventListener("load", rescale);

  window.orgPpt = {
    goTo: goTo, next: next, prev: prev,
    slideCount: slides.length,
    state: state
  };
})();
