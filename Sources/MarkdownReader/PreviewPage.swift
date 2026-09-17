import AppKit

/// The static page the preview web view loads once. Content, style and
/// navigation are then driven through `window.reader` without reloading.
///
/// Compiled in as strings rather than shipped as resource files because
/// `Packaging/build-app.sh` assembles the bundle by hand, and `Bundle.module`
/// lookups in that layout are fragile.
enum PreviewPage {
    static var shell: String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>\(stylesheet)</style></head>
        <body class="sans"><main id="root" class="content"></main>
        <script>\(script)</script></body></html>
        """
    }

    /// Typography follows `Theme` (body 15.5pt, headings 32/25/21/18.5/17/16,
    /// leading 1.5, inset 34x32). Element treatments follow menubar-notes'
    /// editor stylesheet: accent-coloured markers, quote bar and checkboxes,
    /// flat code grounds, hairline rules.
    static let stylesheet = """
    :root {
      --accent: #E5484D;
      --t1: #1C1C1E; --t2: #6B6B70; --t3: #9A9AA1;
      --hair: rgba(0, 0, 0, .08);
      --codebg: #F2F1EE;
      --link: #2D6BB8;
      --measure: 560px;
      --zoom: 1;
      --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      --font-serif: ui-serif, "New York", Georgia, serif;
      --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
      --font-body: var(--font-sans);
      color-scheme: light dark;
    }
    @media (prefers-color-scheme: dark) {
      :root { --t1: #EDEDEF; --t2: #9A9AA1; --t3: #6B6B70; --hair: rgba(255, 255, 255, .09); --codebg: #26262B; --link: #6FA8E8; }
    }
    html { font-size: calc(15.5px * var(--zoom)); }
    html, body { margin: 0; padding: 0; background: transparent; }
    body {
      color: var(--t1);
      font-family: var(--font-body);
      line-height: 1.5;
      padding: 32px 34px;
      box-sizing: border-box;
      -webkit-font-smoothing: antialiased;
      -webkit-text-size-adjust: none;
      overflow-x: hidden;
    }
    body.serif { --font-body: var(--font-serif); }
    body.mono { --font-body: var(--font-mono); }
    .content { max-width: var(--measure); margin: 0 auto; word-break: break-word; overflow-wrap: anywhere; }
    .content > :first-child { margin-top: 0 !important; }
    .content > :last-child { margin-bottom: 0; }

    p { margin: 0 0 .775rem; }
    h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.14; margin: 1.16rem 0 .52rem; }
    h1 { font-size: 2.065rem; font-weight: 700; letter-spacing: -.0125em; margin-top: 1.68rem; }
    h2 { font-size: 1.613rem; letter-spacing: -.016em; margin-top: 1.68rem; }
    h3 { font-size: 1.355rem; }
    h4 { font-size: 1.194rem; }
    h5 { font-size: 1.097rem; }
    h6 { font-size: 1.032rem; }
    strong { font-weight: 600; }
    s { text-decoration-color: var(--t3); }

    a {
      color: var(--link);
      text-decoration: underline;
      text-decoration-color: color-mix(in srgb, var(--link) 40%, transparent);
      text-underline-offset: 2px;
      border-radius: 3px;
      cursor: pointer;
      transition: text-decoration-color 120ms linear, background 120ms linear;
    }
    a:hover { text-decoration-color: var(--link); background: color-mix(in srgb, var(--link) 10%, transparent); }
    a:active { background: color-mix(in srgb, var(--link) 22%, transparent); }

    code { font-family: var(--font-mono); font-size: .9em; background: var(--codebg); padding: 1px 5px; border-radius: 4px; }
    .code { position: relative; margin: 0 0 .775rem; }
    .code pre {
      margin: 0;
      font-family: var(--font-mono);
      font-size: .839rem;
      line-height: 1.5;
      background: var(--codebg);
      padding: 10px 12px;
      border-radius: 8px;
      overflow-x: auto;
      white-space: pre;
    }
    .code pre code { background: none; padding: 0; border-radius: 0; font-size: inherit; }
    .copy {
      position: absolute; top: 6px; right: 6px;
      font: inherit; font-size: .72rem; line-height: 1.4;
      color: var(--t2);
      background: color-mix(in srgb, var(--t1) 6%, transparent);
      border: 1px solid var(--hair);
      border-radius: 5px;
      padding: 2px 8px;
      opacity: 0;
      cursor: default;
      transition: opacity 120ms linear, color 120ms linear;
    }
    .code:hover .copy, .copy:focus-visible { opacity: 1; }
    .copy:hover { color: var(--t1); }
    .raw { font-family: var(--font-mono); color: var(--t3); font-size: .85em; }
    pre.raw { white-space: pre-wrap; margin: 0 0 .775rem; }

    blockquote {
      margin: 0 0 .775rem;
      padding: 0 0 0 12px;
      border-left: 2.5px solid var(--accent);
      color: var(--t2);
    }
    blockquote > :last-child { margin-bottom: 0; }
    hr { border: 0; border-top: 1px solid var(--hair); margin: 16px 0; }

    ul, ol { margin: 0 0 .775rem; padding: 0 0 0 26px; }
    li { margin: 0 0 4px; }
    li > p { margin: 0; }
    li > ul, li > ol, li > .code, li > blockquote { margin: 4px 0 0; }
    ol li::marker { color: var(--accent); font-weight: 500; font-variant-numeric: tabular-nums; }
    ul li::marker { color: var(--accent); }
    ul.tasks { list-style: none; padding-left: 0; }
    ul.tasks > li:not(.task) { list-style: disc; margin-left: 26px; }
    li.task { display: flex; gap: 10px; align-items: flex-start; }
    li.task > input {
      appearance: none; -webkit-appearance: none;
      flex-shrink: 0; position: relative;
      margin: calc((1.5em - 16px) / 2) 0 0;
      width: 16px; height: 16px;
      border-radius: 4px;
      border: 1.5px solid var(--t3);
      background: transparent;
      cursor: default;
      transition: background 150ms cubic-bezier(.2, .9, .25, 1), border-color 150ms;
    }
    li.task > input:checked { background: var(--accent); border-color: var(--accent); }
    li.task > input:checked::after {
      content: ''; position: absolute; left: 4.5px; top: 1.5px;
      width: 4px; height: 8px;
      border: solid #fff; border-width: 0 1.6px 1.6px 0;
      transform: rotate(45deg);
    }
    li.task > input:focus-visible { outline: 2px solid color-mix(in srgb, var(--accent) 50%, transparent); outline-offset: 2px; }
    li.task > .task-body { flex: 1; min-width: 0; }
    li[data-checked="true"] > .task-body > p {
      color: var(--t3);
      text-decoration: line-through;
      text-decoration-color: color-mix(in srgb, var(--accent) 50%, transparent);
    }

    .table-wrap { overflow-x: auto; margin: 0 0 .775rem; }
    table { border-collapse: collapse; font-variant-numeric: tabular-nums; }
    th, td { padding: 5px 14px 5px 0; text-align: left; vertical-align: top; border-bottom: 1px solid var(--hair); }
    th:last-child, td:last-child { padding-right: 0; }
    th { font-weight: 600; border-bottom-color: color-mix(in srgb, var(--t3) 60%, transparent); }
    tbody tr:last-child td { border-bottom: 0; }

    img { max-width: 100%; height: auto; display: block; border-radius: 4px; margin: 0 0 .25rem; }
    img.broken { display: none; }
    .img-missing { color: var(--t2); font-style: italic; }

    ::selection { background: color-mix(in srgb, var(--accent) 24%, transparent); }
    @media (prefers-reduced-motion: reduce) { * { transition-duration: 0ms !important; } }
    """

    static let script = """
    (() => {
      const root = document.getElementById('root');
      const native = window.webkit && webkit.messageHandlers && webkit.messageHandlers.native;
      const post = (message) => { if (native) native.postMessage(message); };
      const blocks = () => root.querySelectorAll('[data-line]:not(input)');

      // The source line at the top of the viewport. Hit-test first so a long
      // block reports itself, then fall back to the first block below the edge.
      function visibleLine() {
        const rect = root.getBoundingClientRect();
        for (const y of [8, 24, 48]) {
          for (const x of [rect.left + 4, rect.left + rect.width / 2]) {
            const el = document.elementFromPoint(x, y);
            const hit = el && el.closest && el.closest('[data-line]');
            if (hit && hit.tagName !== 'INPUT') return Number(hit.dataset.line) || 1;
          }
        }
        for (const el of blocks()) { if (el.getBoundingClientRect().top >= 0) return Number(el.dataset.line) || 1; }
        return 1;
      }
      function report() { post({ type: 'scroll', y: window.scrollY, line: visibleLine() }); }

      let ticking = false;
      window.addEventListener('scroll', () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => { ticking = false; report(); });
      }, { passive: true });

      function targetFor(line) {
        let best = null, bestDelta = Infinity;
        for (const el of blocks()) {
          const n = Number(el.dataset.line);
          if (!n) continue;
          const d = Math.abs(n - line);
          if (d < bestDelta) { best = el; bestDelta = d; if (d === 0) break; }
        }
        return best;
      }
      function jump(line) {
        if (!line || line <= 1) { window.scrollTo(0, 0); return; }
        const el = targetFor(line);
        if (!el) return;
        window.scrollTo(0, Math.max(0, el.getBoundingClientRect().top + window.scrollY - 12));
      }

      root.addEventListener('change', (e) => {
        const input = e.target;
        if (!(input instanceof HTMLInputElement) || input.type !== 'checkbox') return;
        const li = input.closest('li.task');
        if (li) li.dataset.checked = String(input.checked);
        post({ type: 'toggleTask', line: Number(input.dataset.line) });
      });
      root.addEventListener('click', (e) => {
        const button = e.target.closest && e.target.closest('.copy');
        if (!button) return;
        const code = button.parentElement.querySelector('code');
        post({ type: 'copyCode', code: code ? code.textContent : '' });
        button.textContent = 'Copied';
        setTimeout(() => { button.textContent = 'Copy'; }, 1200);
      });
      root.addEventListener('error', (e) => {
        const img = e.target;
        if (!(img instanceof HTMLImageElement)) return;
        img.classList.add('broken');
        const next = img.nextElementSibling;
        if (next && next.classList.contains('img-missing')) return;
        const note = document.createElement('span');
        note.className = 'img-missing';
        note.textContent = 'Image unavailable: ' + (img.alt || 'Image');
        img.after(note);
      }, true);

      window.reader = {
        setContent({ html, line, keepScroll }) {
          const y = window.scrollY;
          root.innerHTML = html;
          if (keepScroll) window.scrollTo(0, y); else jump(line || 1);
          report();
        },
        setStyle({ measure, zoom, face, accent }) {
          const style = document.documentElement.style;
          style.setProperty('--measure', measure + 'px');
          style.setProperty('--zoom', String(zoom));
          if (accent) style.setProperty('--accent', accent);
          document.body.classList.remove('sans', 'serif', 'mono');
          document.body.classList.add(face);
        },
        jump({ line }) { jump(line); },
        visibleLine,
        reloadImages() {
          root.querySelectorAll('.img-missing').forEach((note) => note.remove());
          root.querySelectorAll('img').forEach((img) => {
            img.classList.remove('broken');
            const base = (img.getAttribute('src') || '').replace(/[?&]r=\\d+$/, '');
            img.setAttribute('src', base + (base.includes('?') ? '&' : '?') + 'r=' + Date.now());
          });
        },
        clearSelection() { const s = window.getSelection(); if (s) s.removeAllRanges(); },
      };
      post({ type: 'ready' });
    })();
    """
}

extension NSColor {
    /// `#rrggbb` in sRGB, for handing a system colour to CSS.
    var cssHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#E5484D" }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()), b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
