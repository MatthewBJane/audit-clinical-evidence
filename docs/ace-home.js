/* ACE home page: the hero glitch, the navbar wordmark hand-off, the totals
   readout and the ACE-RIV grid. Loaded by index.qmd only. Styling lives in
   styles.css under "HOME PAGE". Everything here is decoration on top of a
   page that is complete without it; with reduced motion asked for, only the
   non-animated parts run. */
(function () {
  "use strict";

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var body = document.body;
  var hero = document.getElementById("ace-hero");
  var mark = document.getElementById("ace-hero-mark");
  if (!hero || !mark) return;

  /* ---------- is the hero on screen? (the ambient bursts only run while it is) */
  if ("IntersectionObserver" in window) {
    if (mark.getBoundingClientRect().bottom > 90) body.classList.add("ace-hero-in-view");
    new IntersectionObserver(function (entries) {
      body.classList.toggle("ace-hero-in-view", entries[0].isIntersecting);
    }, { rootMargin: "-90px 0px 0px 0px" }).observe(mark);
  }

  /* ---------- ACE-RIV grid readout */
  var grid = document.getElementById("ace-riv-grid");
  var readout = document.getElementById("ace-riv-readout");
  function show(btn) {
    if (!btn || !readout) return;
    grid.querySelectorAll(".ace-rc.is-selected").forEach(function (b) { b.classList.remove("is-selected"); });
    btn.classList.add("is-selected");
    var c = +btn.dataset.count || 0;
    readout.innerHTML = "";
    [["ace-riv-readout-key", "RIV " + btn.dataset.riv],
     ["ace-riv-readout-name", btn.dataset.name],
     ["ace-riv-readout-count", c ? c + " instance" + (c === 1 ? "" : "s") + " documented so far"
                                 : "Not yet documented in a published report"]
    ].forEach(function (p) {
      var s = document.createElement("span");
      s.className = p[0];
      s.textContent = p[1];
      readout.appendChild(s);
    });
  }
  if (grid) {
    ["mouseover", "focusin", "click"].forEach(function (ev) {
      grid.addEventListener(ev, function (e) { show(e.target.closest(".ace-rc")); });
    });
    var first = grid.querySelector('.ace-rc[data-riv="' +
      ((readout && readout.textContent.match(/RIV ([0-9.]+)/)) || [0, ""])[1] + '"]');
    if (first) first.classList.add("is-selected");
  }

  /* ---------- subscribe: post the address to the Google Form behind the
     private signup Sheet. The form targets a hidden iframe, so the page never
     navigates; the response is cross-origin and unreadable, so the message
     confirms the submission rather than a server reply. */
  document.querySelectorAll(".ace-subscribe").forEach(function (form) {
    var input = form.querySelector(".ace-subscribe-input");
    var msg = form.querySelector(".ace-subscribe-msg");
    var btn = form.querySelector(".ace-subscribe-btn");
    form.addEventListener("submit", function (e) {
      var v = (input.value || "").trim();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) {
        e.preventDefault(); msg.className = "ace-subscribe-msg"; msg.textContent = "Enter an email address."; input.focus(); return;
      }
      input.value = v; btn.disabled = true; btn.textContent = "Sending";
      setTimeout(function () {
        form.classList.add("is-done"); msg.className = "ace-subscribe-msg is-ok";
        msg.textContent = "Added. You will get an email when the next report is published.";
      }, 700);
    });
  });

  /* ---------- copy the contact address */
  document.querySelectorAll(".ace-mailbox-copy").forEach(function (btn) {
    var label = btn.textContent;
    btn.addEventListener("click", function () {
      var text = btn.dataset.copy;
      function done(msg) { btn.textContent = msg; setTimeout(function () { btn.textContent = label; }, 1600); }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { done("Copied"); }, function () { done("Press ⌘C"); select(); });
      } else { select(); done("Press ⌘C"); }
      function select() {
        var a = btn.parentNode.querySelector(".ace-mailbox-addr");
        if (!a) return;
        var r = document.createRange(); r.selectNodeContents(a);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
      }
    });
  });

  if (reduce) return;

  /* ---------- hero glitch ---------- */
  // only the drawn layers change; .ace-mark-size keeps the box the size of "ACE"
  var layers = mark.querySelectorAll(".ace-mark-base, .ace-mark-ghost");
  var deck = document.getElementById("ace-hero-deck");
  var sweep = hero.querySelector(".ace-hero-sweep");
  var GLYPHS = "ACE#%&@$XZ0187/\\<>?*";
  var DECK = deck ? deck.textContent : "";
  function setMark(t) { layers.forEach(function (l) { l.textContent = t; }); }
  function rand(n) { return Math.floor(Math.random() * n); }

  // horizontal tear bars that flash across the hero during a burst
  function tears(slow) {
    var s = slow || 1;
    var n = slow ? 3 + rand(3) : 4 + rand(4);
    for (var i = 0; i < n; i++) {
      var d = document.createElement("div");
      d.className = "ace-hero-tear " + (Math.random() < 0.5 ? "is-c" : "is-m");
      d.style.top = (8 + Math.random() * 84) + "%";
      d.style.left = (Math.random() * 60) + "%";
      d.style.width = (12 + Math.random() * 40) + "%";
      d.style.height = (1 + Math.random() * 5) + "px";
      if (slow) d.style.transition = "transform " + (0.25 * s) + "s steps(3, end)";
      hero.appendChild(d);
      (function (el, j) {
        setTimeout(function () { el.style.transform = "translateX(" + (Math.random() * 80 - 40) + "px)"; }, (90 + j * 30) * s);
        setTimeout(function () { el.remove(); }, (180 + Math.random() * 420) * s);
      })(d, i);
    }
  }

  var bursting = false;
  // slow > 1 stretches everything (the intro's closing burst uses 1.4)
  function burst(big, slow) {
    if (bursting) return;
    bursting = true;
    var s = slow || 1;
    mark.style.setProperty("--ace-burst-dur", (0.9 * s).toFixed(2) + "s");
    if (sweep) sweep.style.setProperty("--ace-burst-dur", (0.9 * s).toFixed(2) + "s");
    mark.classList.remove("is-burst"); void mark.offsetWidth; mark.classList.add("is-burst");
    tears(slow); setTimeout(function () { tears(slow); }, 300 * s);
    if (big && sweep) { sweep.classList.remove("is-on"); void sweep.offsetWidth; sweep.classList.add("is-on"); }
    // one letter swaps for a stray glyph mid-burst
    setTimeout(function () {
      var t = "ACE".split(""); t[rand(3)] = GLYPHS[rand(GLYPHS.length)]; setMark(t.join(""));
    }, 260 * s);
    setTimeout(function () { setMark("ACE"); }, 420 * s);
    setTimeout(function () {
      mark.classList.remove("is-burst");
      mark.style.removeProperty("--ace-burst-dur");
      bursting = false;
    }, 900 * s);
  }

  var timer;
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      if (!document.hidden && body.classList.contains("ace-hero-in-view")) burst(Math.random() < 0.35);
      schedule();
    }, 3800 + Math.random() * 2600);
  }

  mark.addEventListener("mouseenter", function () { mark.classList.add("is-storm"); tears(); });
  mark.addEventListener("mouseleave", function () { mark.classList.remove("is-storm"); });
  mark.addEventListener("click", function () { burst(true); });

  // the cyan and magenta channels drift apart as the pointer crosses the hero
  var tx = 0, ty = 0, cx = 0, cy = 0, raf = 0;
  function step() {
    cx += (tx - cx) * 0.12; cy += (ty - cy) * 0.12;
    mark.style.setProperty("--ace-px", cx.toFixed(3));
    mark.style.setProperty("--ace-py", cy.toFixed(3));
    raf = (Math.abs(tx - cx) > 0.002 || Math.abs(ty - cy) > 0.002) ? requestAnimationFrame(step) : 0;
  }
  hero.addEventListener("pointermove", function (e) {
    if (e.pointerType === "touch") return;
    var r = hero.getBoundingClientRect();
    tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
    ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    if (!raf) raf = requestAnimationFrame(step);
  });
  hero.addEventListener("pointerleave", function () { tx = 0; ty = 0; if (!raf) raf = requestAnimationFrame(step); });

  // intro: the mark and the deck line decode from noise, then the first burst
  // The glyphs change on a slow tick (not every frame) so the noise reads as
  // a signal locking on rather than a flicker; letters settle one by one.
  function intro() {
    var t0 = performance.now(), D = 1500, TICK = 90, lastTick = -1;
    (function frame(now) {
      var p = Math.min(1, (now - t0) / D);
      var tick = Math.floor((now - t0) / TICK);
      if (tick !== lastTick || p >= 1) {
        lastTick = tick;
        var out = "";
        for (var i = 0; i < 3; i++) out += (p > (i + 1) / 3.6) ? "ACE"[i] : GLYPHS[rand(GLYPHS.length)];
        setMark(out);
        if (deck) {
          var settled = Math.floor(p * DECK.length), h = "";
          for (var j = 0; j < DECK.length; j++) {
            var ch = DECK[j];
            h += (j < settled || ch === " ") ? ch : '<span class="ace-scr">' + "ACE#%/01"[rand(8)] + "</span>";
          }
          deck.innerHTML = h;
        }
      }
      if (p < 1) { requestAnimationFrame(frame); return; }
      setMark("ACE");
      if (deck) deck.textContent = DECK;
      burst(true, 1.4);
      schedule();
    })(t0);
  }
  // Start once the wordmark font is in, so the decode never plays over
  // fallback letters; give up waiting after 1.2 s.
  var started = false;
  function start() { if (!started) { started = true; intro(); } }
  if (document.fonts && document.fonts.load) {
    document.fonts.load('1em "Rubik Glitch"').then(start, start);
    setTimeout(start, 1200);
  } else {
    start();
  }

  /* ---------- totals: digits scramble, then lock, as they come into view */
  function scramble(el) {
    var v = el.dataset.v || el.textContent, t0 = performance.now();
    el.classList.add("is-scrambling");
    (function f(now) {
      var p = (now - t0) / 700, s = "";
      for (var i = 0; i < v.length; i++) s += p > (i + 1) / (v.length + 0.5) ? v[i] : rand(10);
      el.textContent = s;
      if (p < 1) requestAnimationFrame(f);
      else { el.textContent = v; el.classList.remove("is-scrambling"); }
    })(t0);
  }
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { scramble(e.target); io.unobserve(e.target); }
      });
    }, { threshold: 0.6 });
    document.querySelectorAll(".ace-total-num").forEach(function (n) { io.observe(n); });
  }
})();
