// Motion for the lab-notebook site (main page and appendix). Vanilla JS, no libraries.
// Everything respects prefers-reduced-motion: no autoplay, no count-up, no
// pinned scroll (CSS), and every animation has a pause control.
(function () {
  const REDUCE = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const DATA = document.documentElement.dataset.base || "";

  // ---- Replay data, loaded once ----
  let replayP = null;
  function loadReplay() {
    if (!replayP) {
      const img = src => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
      replayP = Promise.all([
        fetch(DATA + "data/replay_900015.json").then(r => r.json()),
        img(DATA + "data/replay_900015_sprite.png"),
        img(DATA + "data/replay_900015_start.png"),
      ]).then(([data, sprite, start]) => ({ data, sprite, start }));
    }
    return replayP;
  }
  function drawFrame(ctx, R, i, w, h) {
    // i = player index: the canvas before step i (0 = start image).
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, w, h);
    if (i === 0) ctx.drawImage(R.start, 0, 0, w, h);
    else {
      const f = i - 1, t = R.data.tile, c = R.data.cols;
      ctx.drawImage(R.sprite, (f % c) * t, Math.floor(f / c) * t, t, t, 0, 0, w, h);
    }
  }
  function gridRows(cells) {
    const g = [];
    for (let r = 0; r < 100; r++) g.push(new Array(100).fill("."));
    for (const ch in cells) for (const k of cells[ch]) g[Math.floor(k / 100)][k % 100] = ch;
    return g;
  }
  function gridHTML(rows) {
    return rows.map(row => {
      let s = "", run = "", cls = null;
      const flush = () => { if (run) s += cls ? `<span class="${cls}">${run}</span>` : run; run = ""; };
      for (const ch of row) {
        const c = ch === "H" ? "h" : ch === "." ? null : "c c" + ch;
        if (c !== cls) { flush(); cls = c; }
        run += ch;
      }
      flush();
      return s;
    }).join("\n");
  }
  function cursorOf(st) { const h = st.cells.H ? st.cells.H[0] : 5050; return [h % 100, Math.floor(h / 100)]; }
  function painted(st) { let n = 0; for (const ch in st.cells) if (ch !== "H") n += st.cells[ch].length; return n; }

  // ---- Hero: the session replays itself on load ----
  document.querySelectorAll("[data-hero]").forEach(hero => {
    const mode = hero.dataset.hero;  // "canvas" or "ascii"
    const cv = hero.querySelector("canvas");
    const pre = hero.querySelector("pre");
    const btn = hero.querySelector("[data-hero-toggle]");
    const stepOut = hero.querySelector("[data-hero-step]");
    let R = null, i = 0, timer = null;
    function show() {
      const n = R.data.steps.length;
      if (cv) drawFrame(cv.getContext("2d"), R, i, cv.width, cv.height);
      if (pre) pre.innerHTML = gridHTML(gridRows(R.data.steps[i].cells));
      if (stepOut) stepOut.textContent = `Step ${i + 1} of ${n}`;
    }
    function stop() { clearInterval(timer); timer = null; if (btn) btn.textContent = btn.dataset.play || "Play replay"; }
    function play() {
      if (i >= R.data.steps.length - 1) i = 0;
      if (btn) btn.textContent = btn.dataset.pause || "Pause replay";
      timer = setInterval(() => {
        if (i >= R.data.steps.length - 1) { stop(); return; }
        i++; show();
      }, mode === "ascii" ? 220 : 160);
    }
    if (btn) btn.addEventListener("click", () => (timer ? stop() : play()));
    loadReplay().then(r => {
      R = r;
      if (REDUCE) { i = R.data.steps.length - 1; show(); stop(); }
      else { i = 0; show(); play(); }
    }).catch(() => { if (stepOut) stepOut.textContent = "Replay data could not be loaded."; });
  });

  // ---- Chapter 5 player (same behavior as the draft's) ----
  const root = document.getElementById("replay");
  if (root) {
    const cv = root.querySelector("canvas"), pre = root.querySelector("pre.ascii");
    const range = root.querySelector("input[type=range]"), playB = root.querySelector("[data-act=play]");
    const zoomB = root.querySelector("[data-act=zoom]"), live = root.querySelector(".readout");
    const out = {}; ["step", "cmd", "pen", "desc"].forEach(k => out[k] = root.querySelector(`[data-out=${k}]`));
    const Z = 21;
    let R = null, i = 0, timer = null, zoomed = false;
    function draw() {
      const st = R.data.steps[i], n = R.data.steps.length;
      drawFrame(cv.getContext("2d"), R, i, cv.width, cv.height);
      const cur = cursorOf(st);
      let rows = gridRows(st.cells);
      if (zoomed) {
        const h = (Z - 1) / 2;
        const c0 = Math.min(100 - Z, Math.max(0, cur[0] - h)), r0 = Math.min(100 - Z, Math.max(0, cur[1] - h));
        rows = rows.slice(r0, r0 + Z).map(r => r.slice(c0, c0 + Z));
      }
      pre.innerHTML = gridHTML(rows);
      pre.classList.toggle("zoom", zoomed);
      const label = `${st.step + 1} of ${n}`;
      out.step.textContent = label;
      out.cmd.textContent = st.command === "pen" ? "pen_tool" : (st.command || "none");
      out.pen.textContent = i === 0 ? "up" : (R.data.steps[i - 1].pen ? "down" : "up");
      out.desc.textContent = `Text grid at step ${st.step + 1}: cursor at column ${cur[0] + 1}, row ${cur[1] + 1}; ${painted(st)} painted cells.`;
      cv.setAttribute("aria-label", `Canvas before step ${st.step + 1}`);
      range.value = i;
      range.setAttribute("aria-valuetext", `Step ${label}, command ${out.cmd.textContent}`);
    }
    function stop() { clearInterval(timer); timer = null; playB.textContent = "Play"; live.setAttribute("aria-live", "polite"); }
    function go() {
      if (i >= R.data.steps.length - 1) i = 0;
      playB.textContent = "Pause"; live.setAttribute("aria-live", "off");
      timer = setInterval(() => { if (i >= R.data.steps.length - 1) { stop(); return; } i++; draw(); }, 450);
    }
    playB.addEventListener("click", () => (timer ? stop() : go()));
    root.querySelector("[data-act=prev]").addEventListener("click", () => { stop(); i = Math.max(0, i - 1); draw(); });
    root.querySelector("[data-act=next]").addEventListener("click", () => { stop(); i = Math.min(R.data.steps.length - 1, i + 1); draw(); });
    range.addEventListener("input", () => { stop(); i = +range.value; draw(); });
    zoomB.addEventListener("click", () => { zoomed = !zoomed; zoomB.setAttribute("aria-pressed", String(zoomed)); if (R) draw(); });
    loadReplay().then(r => { R = r; range.max = R.data.steps.length - 1; i = R.data.steps.length - 1; draw(); root.classList.add("ready"); })
      .catch(() => { root.querySelector("[data-out=err]").hidden = false; });
  }

  // ---- Rail (top bar on phones): highlights the section in view ----
  const trackers = document.querySelectorAll("[data-track]");
  if (trackers.length) {
    const ids = [...new Set([...document.querySelectorAll("[data-track] a[data-ch]")].map(a => a.dataset.ch))];
    const secs = ids.map(id => document.getElementById(id)).filter(Boolean);
    let last = null;
    let ticking = false;
    function update() {
      ticking = false;
      const y = window.innerHeight * 0.4;
      let cur = null;
      for (const s of secs) if (s.getBoundingClientRect().top < y) cur = s.id;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const p = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      trackers.forEach(t => {
        t.style.setProperty("--progress", p.toFixed(4));
        t.querySelectorAll("a[data-ch]").forEach(a => {
          const on = a.dataset.ch === cur;
          a.classList.toggle("current", on);
          if (on) a.setAttribute("aria-current", "true"); else a.removeAttribute("aria-current");
          // In the phone top bar, keep the current entry in view (no page scroll).
          const ol = a.closest("ol");
          if (on && cur !== last && ol.scrollWidth > ol.clientWidth + 1) {
            const l = a.offsetLeft, r = l + a.offsetWidth;
            if (l < ol.scrollLeft || r > ol.scrollLeft + ol.clientWidth) ol.scrollLeft = Math.max(0, l - 16);
          }
        });
      });
      last = cur;
    }
    window.addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  // ---- Counters: count up once when they enter view ----
  const fmt = n => n.toLocaleString("en-US");
  const counters = document.querySelectorAll("[data-count]");
  if (!REDUCE && "IntersectionObserver" in window) {
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        io.unobserve(e.target);
        const el = e.target, end = +el.dataset.count, t0 = performance.now(), dur = 1400;
        const tick = t => {
          const k = Math.min(1, (t - t0) / dur), v = Math.round(end * (1 - Math.pow(1 - k, 3)));
          el.textContent = fmt(v);
          if (k < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
    }, { threshold: 0.6 });
    counters.forEach(el => {
      const r = el.getBoundingClientRect();
      if (r.top > window.innerHeight) { el.textContent = "0"; io.observe(el); }  // only count up from below the fold
    });
  }

  // ---- Compare slider: v3 real against predicted at the same step ----
  document.querySelectorAll("[data-compare]").forEach(fig => {
    const base = fig.querySelector(".cmp-base"), top = fig.querySelector(".cmp-top");
    const handle = fig.querySelector(".cmp-handle"), slider = fig.querySelector(".cmp-range");
    const mode = fig.querySelector("[data-cmp-mode]"), step = fig.querySelector("[data-cmp-step]");
    const topLabel = fig.querySelector("[data-cmp-toplabel]");
    const V3 = document.documentElement.dataset.v3 || DATA + "img/v3/";
    const MODES = {
      onestep: { a: "onestep_real.png", b: "onestep_pred.png", steps: Array.from({ length: 30 }, (_, k) => 10 * (k + 1)), label: "Predicted" },
      imag: { a: "imag_real.png", b: "imag_imag.png", steps: [0, 10, 20, 30, 40, 50, 60, 70, 79], label: "Imagined" },
    };
    function setMode() {
      const m = MODES[mode.value];
      step.innerHTML = m.steps.map((s, k) => `<option value="${k}">${s}</option>`).join("");
      step.value = String(m.steps.length - 1);
      [base, top].forEach((el, j) => {
        el.style.backgroundImage = `url("${V3}${j ? m.b : m.a}")`;
        el.style.backgroundSize = `${m.steps.length * 100}% 100%`;
      });
      topLabel.textContent = m.label;
      setStep();
    }
    function setStep() {
      const n = MODES[mode.value].steps.length, k = +step.value;
      const x = n > 1 ? (k / (n - 1)) * 100 : 0;
      base.style.backgroundPosition = top.style.backgroundPosition = `${x}% 0`;
    }
    function setSplit() {
      const v = +slider.value;
      top.style.clipPath = `inset(0 0 0 ${v}%)`;
      handle.style.left = v + "%";
      slider.setAttribute("aria-valuetext", `${v}% real on the left, ${100 - v}% ${MODES[mode.value].label.toLowerCase()} on the right`);
    }
    mode.addEventListener("change", setMode);
    step.addEventListener("change", setStep);
    slider.addEventListener("input", setSplit);
    setMode(); setSplit();
  });

  // ---- Defined terms: Escape hides an open definition ----
  document.addEventListener("keydown", e => {
    if (e.key !== "Escape") return;
    document.querySelectorAll(".term").forEach(t => t.classList.add("tip-off"));
  });
  document.querySelectorAll(".term").forEach(t => {
    ["mouseenter", "focus"].forEach(ev => t.addEventListener(ev, () => t.classList.remove("tip-off")));
  });

  // ---- Animated GIF: still under reduced motion, with a pause button ----
  document.querySelectorAll("img.anim").forEach(img => {
    const b = img.parentNode.querySelector(".animbtn");
    let on = false;
    const set = v => { on = v; img.src = v ? img.dataset.anim : img.dataset.still; b.textContent = v ? "Pause animation" : "Play animation"; };
    b.hidden = false;
    b.addEventListener("click", () => set(!on));
    set(!REDUCE);
  });

  // ---- Chapter 4: thumbnails switch the large canvas ----
  document.querySelectorAll("[data-switch]").forEach(fig => {
    const thumbs = fig.querySelector(".sw-thumbs"), btns = [...fig.querySelectorAll(".sw-thumb")];
    const show = b => {
      btns.forEach(x => x.setAttribute("aria-pressed", String(x === b)));
      fig.querySelectorAll(".sw-panel").forEach(p => p.classList.toggle("on", p.id === b.getAttribute("aria-controls")));
    };
    btns.forEach(b => b.addEventListener("click", () => show(b)));
    thumbs.hidden = false; fig.classList.add("js-on");
  });

  // ---- Code blocks: a copy button on each, scrolling inside the block ----
  document.querySelectorAll("pre.code").forEach(pre => {
    const b = document.createElement("button");
    b.type = "button"; b.className = "copybtn btn"; b.textContent = "Copy";
    b.addEventListener("click", () => {
      const done = t => { b.textContent = t; setTimeout(() => { b.textContent = "Copy"; }, 1600); };
      if (navigator.clipboard) navigator.clipboard.writeText(pre.textContent).then(() => done("Copied"), () => done("Copy failed"));
      else done("Copy failed");
    });
    pre.parentNode.insertBefore(b, pre);
  });
})();

// Theme button (auto / light / dark), remembered per viewer. The page sets a
// saved theme before first paint; this keeps the button label in step.
(function () {
  const b = document.querySelector(".themebtn");
  if (!b) return;
  const el = document.documentElement;
  const get = () => { try { return localStorage.getItem("theme"); } catch (e) { return null; } };
  const set = v => { try { v ? localStorage.setItem("theme", v) : localStorage.removeItem("theme"); } catch (e) {} };
  const apply = v => { if (v) el.setAttribute("data-theme", v); else el.removeAttribute("data-theme"); b.textContent = "Theme: " + (v ? (v === "dark" ? "Dark" : "Light") : "Auto"); };
  apply(get());
  b.addEventListener("click", () => {
    const order = [null, "light", "dark"];
    const next = order[(order.indexOf(get()) + 1) % 3];
    set(next); apply(next);
  });
})();
