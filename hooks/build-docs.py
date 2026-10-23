#!/usr/bin/env python3
"""Convert nixosOptionsDoc options.json + service.json to beginner-friendly static Wiki HTML.

Reads hooks/options.json and hooks/service.json (either may be absent, but at
least one must exist), merges them, and writes docs/index.html.
Optionally bundles a Screenshots/ directory into docs/screenshots/ and
renders them as a gallery.

Project metadata (name, URLs, description) and all input/output paths are
loaded from ``project.toml`` at the project root. A copy next to the script
is used as a fallback. If no TOML file exists, built-in defaults are used.

Usage (typically from the project root)::

    python3 hooks/build-docs.py
    python3 hooks/build-docs.py --config other.toml
"""
import argparse
import html as _html
import json
import math
import re
import shutil
import sys
from datetime import datetime, timezone
from html import escape
from pathlib import Path

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


CONFIG_CANDIDATES = [ROOT / "project.toml", HERE / "project.toml"]
DEFAULTS = {
    "name": "yo",
    "url": "https://QuackHack-McBlindy.com",
    "url_label": "QuackHack-McBlindy.com",
    "github": None,
    "changelog": None,
    "description": """
<p>
  Welcome to the <strong>{name}</strong> Wiki.<br>
  The options on this website are automatically generated on every release to stay in sync.<br>
</p>
<p>
  Use the <strong>search box</strong> on the left to filter options,<br>
  or click any group to expand it and browse the tree.<br>
</p>
""",
    "quick_start_config": "",
    "sources": ["hooks/options.json", "hooks/service.json"],
    "dst": "docs/index.html",
    "logo": "images/logo.png",
    "screenshot_dirs": ["Screenshots", "screenshots"],
    "screenshot_exts": [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".avif"],
}


_HTML_TAG_RE = re.compile(r"<[^>]*>")

_PLACEHOLDERS = {
    "this option has no description",
    "no description",
    "n/a",
    "na",
    "none",
    "null",
    "todo",
    "tbd",
    "fixme",
    "fill me in",
    "fill this in",
    "document me",
    "document this",
}


def _clean_description(desc):
    if desc is None:
        return ""
    if isinstance(desc, dict):
        return _clean_description(desc.get("text"))
    if not isinstance(desc, str):
        return str(desc) if desc else ""
    text = _HTML_TAG_RE.sub("", desc)
    text = _html.unescape(text)
    text = "".join(c for c in text if c.isprintable() or c.isspace())
    return " ".join(text.split())


def _has_visible_text(desc):
    text = _clean_description(desc)
    if not text:
        return False
    normalized = text.lower().rstrip(".!?:;, ").strip()
    if normalized in _PLACEHOLDERS:
        return False
    return True


def _resolve(root, p):
    p = Path(p)
    return p if p.is_absolute() else (root / p)


def find_config(explicit_path):
    if explicit_path:
        p = Path(explicit_path)
        if not p.exists():
            sys.exit(f"error: config file not found: {p}")
        return p
    for p in CONFIG_CANDIDATES:
        if p.exists():
            return p
    return None


def load_config(explicit_path=None):
    cfg = dict(DEFAULTS)
    cfg_path = find_config(explicit_path)

    if cfg_path is not None:
        if tomllib is None:
            sys.exit(
                f"error: cannot read {cfg_path}: tomllib is unavailable. "
                "Install the 'tomli' package or upgrade to Python 3.11+."
            )
        try:
            with open(cfg_path, "rb") as f:
                raw = tomllib.load(f)
        except Exception as e:
            sys.exit(f"error: failed to parse {cfg_path}: {e}")


        for section_key in ("project", "paths"):
            section = raw.pop(section_key, None)
            if isinstance(section, dict):
                cfg.update(section)
            elif section is not None:
                print(f"warning: [{section_key}] in {cfg_path} is not a table, ignoring",
                      file=sys.stderr)

        raw.pop("options", None)

        for k, v in raw.items():
            if k in DEFAULTS:
                cfg[k] = v
            else:
                print(f"warning: unknown config key {k!r} in {cfg_path}", file=sys.stderr)

        print(f"loaded config from {cfg_path}", file=sys.stderr)
    else:
        print("no project.toml found, using defaults", file=sys.stderr)


    name = cfg["name"]
    if not cfg.get("github"):
        cfg["github"] = f"https://github.com/quackhack-mcblindy/{name.lower()}"
    if not cfg.get("changelog"):
        cfg["changelog"] = f"{cfg['github']}/blob/main/CHANGELOG.md"
    if not cfg.get("url_label"):
        cfg["url_label"] = cfg.get("url", "")


    cfg["description"] = cfg["description"].replace("{name}", name)

    cfg["sources"] = [_resolve(ROOT, p) for p in cfg["sources"]]
    cfg["dst"] = _resolve(ROOT, cfg["dst"])
    cfg["logo"] = _resolve(ROOT, cfg["logo"])
    cfg["screenshot_dirs"] = [_resolve(ROOT, p) for p in cfg["screenshot_dirs"]]
    cfg["screenshot_exts"] = set(cfg["screenshot_exts"])

    return cfg

def parse_args(argv=None):
    p = argparse.ArgumentParser(
        prog=Path(__file__).name,
        description="Generate a static Wiki HTML page from nixosOptionsDoc JSON.",
    )
    p.add_argument(
        "--config",
        metavar="PATH",
        default=None,
        help="Path to project.toml "
             "(default: search project root, then next to this script)",
    )

    return p.parse_args(argv)



STYLES = r"""
:root {
  --bg: #ffffff;
  --fg: #1f2328;
  --muted: #656d76;
  --border: #d0d7de;
  --code-bg: #f6f8fa;
  --link: #0969da;
  --sidebar-bg: #f6f8fa;
  --hover: #eaeef2;
}
[data-theme="dark"] {
  --bg: #0d1117;
  --fg: #e6edf3;
  --muted: #8b949e;
  --border: #30363d;
  --code-bg: #161b22;
  --link: #58a6ff;
  --sidebar-bg: #161b22;
  --hover: #21262d;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  background: var(--bg);
  color: var(--fg);
  line-height: 1.5;
}
header {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: .8em;
  padding: .6em 1.2em;
  border-bottom: 1px solid var(--border);
}
header .logo { height: 2em; width: auto; display: block; }
header h1 { margin: 0; font-size: 1.15em; font-weight: 600; }
#theme-toggle {
  margin-left: auto;
  background: none;
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: .35em .65em;
  cursor: pointer;
  font-size: 1em;
  color: var(--fg);
}
#theme-toggle:hover { background: var(--hover); }

.layout {
  flex: 1;
  display: grid;
  grid-template-columns: 300px 1fr;
  min-height: 0;
}

#sidebar {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--sidebar-bg);
  border-right: 1px solid var(--border);
}
#sidebar-header {
  flex-shrink: 0;
  padding: .9em 1em .7em;
  border-bottom: 1px solid var(--border);
}
.sidebar-title {
  margin: 0 0 .6em;
  font-size: .8em;
  text-transform: uppercase;
  letter-spacing: .07em;
  color: var(--muted);
  font-weight: 700;
}
#sidebar input {
  width: 100%;
  padding: .45em .7em;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--bg);
  color: var(--fg);
  font-size: .95em;
}
#sidebar-scroll {
  flex: 1;
  overflow-y: auto;
  padding: .8em 1em 1em;
}
#sidebar-scroll ul { list-style: none; padding-left: .9em; margin: 0; }
#sidebar-scroll > ul { padding-left: 0; }
#sidebar-scroll ul li { margin: .1em 0; }
#sidebar-scroll ul a {
  display: inline-block;
  padding: .15em .3em;
  border-radius: 4px;
  color: var(--fg);
  text-decoration: none;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: .88em;
}
#sidebar-scroll ul a:hover { color: var(--link); background: var(--hover); }
#sidebar-scroll ul details > summary {
  cursor: pointer;
  padding: .15em .3em;
  border-radius: 4px;
  list-style: none;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: .88em;
  color: var(--link);
  user-select: none;
}
#sidebar-scroll ul details > summary:hover { background: var(--hover); }
#sidebar-scroll ul details > summary::-webkit-details-marker { display: none; }
#sidebar-scroll ul details > summary::marker { content: ""; }
#sidebar-scroll ul details > summary::before {
  content: '▸';
  display: inline-block;
  width: 1em;
  color: var(--muted);
  transition: transform .15s;
}
#sidebar-scroll ul details[open] > summary::before { transform: rotate(90deg); }

.screenshots-link {
  display: inline-flex;
  align-items: center;
  gap: .35em;
  padding: .3em .5em;
  margin-bottom: .8em;
  border-radius: 4px;
  color: var(--link);
  text-decoration: none;
  font-size: .9em;
  font-weight: 500;
}
.screenshots-link:hover { background: var(--hover); }
.screenshots-link .screenshots-count {
  color: var(--muted);
  font-weight: 400;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: .9em;
}

.screenshots-link,
.quickstart-link {
  display: flex;
  width: fit-content;
  align-items: center;
  gap: .35em;
  padding: .3em .5em;
  margin-bottom: .4em;          /* was .8em — each link now has its own row */
  border-radius: 4px;
  color: var(--link);
  text-decoration: none;
  font-size: .9em;
  font-weight: 500;
}
.screenshots-link:hover,
.quickstart-link:hover { background: var(--hover); }

#sidebar-footer {
  flex-shrink: 0;
  padding: .8em 1em;
  border-top: 1px solid var(--border);
  font-size: .85em;
  line-height: 1.5;
  background: var(--sidebar-bg);
}
a.footer-project {
  display: inline-block;
  font-weight: 600;
  color: var(--fg);
  text-decoration: none;
}
a.footer-project:hover { color: var(--link); }
.footer-coverage {
  color: var(--muted);
  font-size: .8em;
  margin-bottom: .4em;
}
.footer-coverage .coverage-value {
  color: var(--fg);
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-weight: 600;
}
.footer-coverage.low .coverage-value { color: #cf222e; }
[data-theme="dark"] .footer-coverage.low .coverage-value { color: #ff7b72; }
.footer-link {
  display: block;
  color: var(--link);
  text-decoration: none;
  padding: .1em 0;
  word-break: break-all;
}
.footer-link:hover { text-decoration: underline; }
.footer-build {
  color: var(--muted);
  font-size: .72em;
  margin-top: .5em;
  font-family: ui-monospace, SFMono-Regular, monospace;
}

main {
  overflow-y: auto;
  padding: 1.5em 2em 4em;
  scroll-behavior: smooth;
}
main > * { max-width: 900px; }

.intro {
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1em 1.4em;
  margin-bottom: 1.8em;
  background: var(--sidebar-bg);
  font-size: .97em;
}
.intro > p:first-child { margin-top: 0; }
.intro > p:last-child  { margin-bottom: 0; }

.quickstart-section { margin: 1.5em 0 2em; scroll-margin-top: 1em; }

details.quickstart {
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--sidebar-bg);
  overflow: hidden;
}
details.quickstart > summary {
  cursor: pointer;
  padding: .7em 1em;
  font-weight: 600;
  user-select: none;
  list-style: none;
}
details.quickstart > summary::-webkit-details-marker { display: none; }
details.quickstart > summary::marker { content: ""; }
details.quickstart > summary::before {
  content: '▸';
  display: inline-block;
  width: 1em;
  color: var(--muted);
  transition: transform .15s;
}
details.quickstart[open] > summary::before { transform: rotate(90deg); }
details.quickstart > summary:hover { background: var(--hover); }

details.quickstart > pre {
  margin: 0;
  padding: 1em;
  border-top: 1px solid var(--border);
  background: var(--code-bg);
  overflow-x: auto;
  white-space: pre;          /* override the global pre-wrap */
  word-break: normal;
  border-radius: 0;
}

.screenshots-section,
.options-section { margin: 1.5em 0 2em; scroll-margin-top: 1em; }
.screenshots-section h2,
.options-section h2 {
  font-size: 1.1em;
  margin: 0 0 .8em;
  padding-bottom: .3em;
  border-bottom: 1px solid var(--border);
}

.screenshots-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 1em;
}
.screenshot {
  margin: 0;
  border: 1px solid var(--border);
  border-radius: 8px;
  overflow: hidden;
  background: var(--sidebar-bg);
}
.screenshot a { display: block; line-height: 0; }
.screenshot img {
  width: 100%;
  height: 160px;
  object-fit: cover;
  display: block;
  transition: transform .2s;
}
.screenshot:hover img { transform: scale(1.05); }
.screenshot figcaption {
  padding: .5em .7em;
  font-size: .85em;
  color: var(--muted);
  text-align: center;
  text-transform: capitalize;
  border-top: 1px solid var(--border);
}

details.group { margin: .15em 0; }
details.group > summary {
  cursor: pointer;
  padding: .4em .55em;
  border-radius: 4px;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-weight: 600;
  color: var(--link);
  user-select: none;
}
details.group > summary:hover { background: var(--hover); }
details.group > summary .count {
  font-weight: 400;
  color: var(--muted);
  font-size: .85em;
}
details.group > .children {
  margin-left: .5em;
  padding-left: 1em;
  border-left: 1px solid var(--border);
}
.option { margin: 1em 0; }
.option > h3 {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 1em;
  margin: .2em 0 .4em;
}
dl {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: .25em 1em;
  margin: 0;
}
dt {
  font-weight: 600;
  font-size: .82em;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: .03em;
  padding-top: .15em;
}
dd { margin: 0; min-width: 0; }
dd.undocumented {
  color: var(--muted);
  font-style: italic;
}
code, pre {
  background: var(--code-bg);
  border-radius: 4px;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: .9em;
}
code { padding: .1em .35em; }
pre {
  padding: .5em .7em;
  overflow-x: auto;
  white-space: pre-wrap;
  word-break: break-word;
  margin: 0;
}
dd > p:first-child { margin-top: 0; }
dd > p:last-child  { margin-bottom: 0; }
.hidden { display: none !important; }
#empty {
  display: none;
  color: var(--muted);
  font-style: italic;
  padding: 2em;
  text-align: center;
}
.option, details.group { scroll-margin-top: 1em; }

@media (max-width: 700px) {
  body { height: auto; overflow: visible; }
  .layout { grid-template-columns: 1fr; min-height: auto; }
  #sidebar {
    max-height: 45vh;
    border-right: none;
    border-bottom: 1px solid var(--border);
  }
  main { overflow: visible; padding: 1em; }
}
"""

SCRIPT = r"""
(function () {
  const html = document.documentElement;
  const toggle = document.getElementById('theme-toggle');

  function applyTheme(t) {
    html.dataset.theme = t;
    toggle.textContent = t === 'dark' ? '☀️' : '🌙';
    toggle.title = t === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';
    try { localStorage.setItem('zigduck-theme', t); } catch (e) {}
  }
  let saved = null;
  try { saved = localStorage.getItem('zigduck-theme'); } catch (e) {}
  if (saved === 'dark' || saved === 'light') applyTheme(saved);
  else applyTheme(matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  toggle.addEventListener('click', () => {
    applyTheme(html.dataset.theme === 'dark' ? 'light' : 'dark');
  });

  const options = Array.from(document.querySelectorAll('main .option'));
  const allDetails = Array.from(document.querySelectorAll('details'));
  const sideLis = Array.from(document.querySelectorAll('#sidebar-scroll li'));
  const search = document.getElementById('search');
  const empty = document.getElementById('empty');
  const main = document.getElementById('main');

  const depth = el => { let d = 0; while (el.parentElement) { d++; el = el.parentElement; } return d; };
  const detailsDesc = allDetails.slice().sort((a, b) => depth(b) - depth(a));
  const sideLisDesc = sideLis.slice().sort((a, b) => depth(b) - depth(a));

  const initialOpen = new Map();
  allDetails.forEach(d => initialOpen.set(d, d.open));

  function openAncestors(el) {
    let p = el.parentElement;
    while (p) {
      if (p.tagName === 'DETAILS') p.open = true;
      p = p.parentElement;
    }
  }

  document.querySelectorAll('#sidebar a').forEach(a => {
    a.addEventListener('click', (e) => {
      const id = decodeURIComponent(a.getAttribute('href').slice(1));
      const target = document.getElementById(id);
      if (!target) return;
      e.preventDefault();
      openAncestors(target);
      openAncestors(a);
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  search.addEventListener('input', () => {
    const q = search.value.toLowerCase().trim();

    options.forEach(el => el.classList.remove('hidden'));
    allDetails.forEach(d => d.classList.remove('hidden'));
    sideLis.forEach(li => li.classList.remove('hidden'));

    if (!q) {
      initialOpen.forEach((open, d) => { d.open = open; });
      empty.style.display = 'none';
      return;
    }

    options.forEach(el => {
      if (!el.textContent.toLowerCase().includes(q)) el.classList.add('hidden');
    });

    detailsDesc.forEach(d => {
      if (!d.classList.contains('group')) return;
      const summary = d.querySelector(':scope > summary');
      const summaryMatch = summary && summary.textContent.toLowerCase().includes(q);
      if (summaryMatch) d.querySelectorAll('.hidden').forEach(x => x.classList.remove('hidden'));
      const hasVisible = d.querySelector('.option:not(.hidden)');
      if (summaryMatch || hasVisible) d.open = true;
      else d.classList.add('hidden');
    });

    sideLisDesc.forEach(li => {
      const own = li.querySelector(':scope > a, :scope > details > summary');
      const ownMatch = own && own.textContent.toLowerCase().includes(q);
      const det = li.querySelector(':scope > details');

      if (ownMatch) {
        li.querySelectorAll('li').forEach(x => x.classList.remove('hidden'));
        li.querySelectorAll('details').forEach(x => x.open = true);
      }

      const childVisible = Array.from(li.querySelectorAll(':scope > details > ul > li'))
        .some(c => !c.classList.contains('hidden'));

      if (!ownMatch && !childVisible) li.classList.add('hidden');
      else if (det) det.open = true;
    });

    empty.style.display = main.querySelector('.option:not(.hidden)') ? 'none' : 'block';
  });

  toggle.textContent = html.dataset.theme === 'dark' ? '☀️' : '🌙';
})();
"""

TEMPLATE = """<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
<title>{PROJECT_NAME} options</title>
<style>
{STYLES}
</style>
</head>
<body>
<header>
  <img src="images/logo.png" alt="" class="logo">
  <h1>{PROJECT_NAME}</h1>
  <button id="theme-toggle" title="Toggle theme">🌙</button>
</header>
<div class="layout">
  <aside id="sidebar">
    <div id="sidebar-header">
      <h2 class="sidebar-title">Options</h2>
      <input id="search" type="search" placeholder="Filter options…" autofocus>
    </div>
    <div id="sidebar-scroll">
      {quickstart_link}
      {screenshots_link}
      {sidebar}
    </div>
    <div id="sidebar-footer">
      <a class="footer-project" href="{PROJECT_GITHUB}" target="_blank" rel="noopener">{PROJECT_NAME}</a>
      {coverage}
      <a class="footer-link" href="{CHANGELOG_URL}" target="_blank" rel="noopener">Changelog</a>
      <a class="footer-link" href="{PROJECT_URL}" target="_blank" rel="noopener">{PROJECT_URL_LABEL}</a>
      <div class="footer-build">{built_at}</div>
    </div>
  </aside>
  <main id="main">
    <section class="intro">{PROJECT_DESCRIPTION}</section>
    {quick_start}
    {screenshots}
    <section class="options-section" id="options">
      <h2>Options</h2>
      {content}
      <p id="empty">No matching options.</p>
    </section>
  </main>
</div>
<script>
{SCRIPT}
</script>
</body>
</html>
"""


class Node:
    __slots__ = ('name', 'option', 'children')
    def __init__(self, name):
        self.name = name
        self.option = None
        self.children = {}


def build_tree(options):
    root = Node('')
    for name, opt in options.items():
        node = root
        for part in name.split('.'):
            node = node.children.setdefault(part, Node(part))
        node.option = opt
    return root


def count_leaves(node):
    if not node.children:
        return 1 if node.option else 0
    return sum(count_leaves(c) for c in node.children.values())


def render_option_body(opt):
    parts = ['<dl>']
    if t := opt.get('type'):
        parts.append(f'<dt>Type</dt><dd><code>{escape(t)}</code></dd>')
    if d := (opt.get('default') or {}).get('text'):
        parts.append(f'<dt>Default</dt><dd><code>{escape(d)}</code></dd>')
    if e := (opt.get('example') or {}).get('text'):
        parts.append(f'<dt>Example</dt><dd><pre>{escape(e)}</pre></dd>')
    desc_raw = opt.get('description')
    if _has_visible_text(desc_raw):
        parts.append(f'<dt>Description</dt><dd>{desc_raw}</dd>')
    else:
        parts.append(
            '<dt>Description</dt>'
            '<dd class="undocumented">⚠ Not documented</dd>'
        )
    parts.append('</dl>')
    return ''.join(parts)


def render_node(node, path, depth):
    full = '.'.join(path)
    children = sorted(node.children.values(), key=lambda n: n.name)
    if not children:
        body = render_option_body(node.option) if node.option else ''
        return f'<div class="option" id="{escape(full)}"><h3>{escape(node.name)}</h3>{body}</div>'
    parts = []
    if node.option:
        parts.append(render_option_body(node.option))
    for c in children:
        parts.append(render_node(c, path + [c.name], depth + 1))
    n = count_leaves(node)
    return (
        f'<details class="group" id="{escape(full)}">'
        f'<summary>{escape(node.name)} <span class="count">({n})</span></summary>'
        f'<div class="children">{"".join(parts)}</div>'
        f'</details>'
    )


def render_sidebar_item(node, path):
    full = '.'.join(path)
    children = sorted(node.children.values(), key=lambda n: n.name)
    if not children:
        return f'<li><a href="#{escape(full)}">{escape(node.name)}</a></li>'
    sub = ''.join(render_sidebar_item(c, path + [c.name]) for c in children)
    return (
        f'<li><details class="sidebar-group">'
        f'<summary>{escape(node.name)}</summary>'
        f'<ul>{sub}</ul>'
        f'</details></li>'
    )


def _read_json_file(p):
    """Read a JSON file. Returns (data, error_or_None).

    - Uses utf-8-sig so a leading UTF-8 BOM is stripped automatically.
    - If the file is empty/whitespace-only, returns ({}, "empty") so the
      caller can decide what to do.
    - On parse error, returns (None, "human-readable message") including
      a hex preview of the first 32 bytes so you can see what's wrong.
    """
    try:
        text = p.read_text(encoding='utf-8-sig')
    except UnicodeDecodeError as e:
        return None, f'not valid UTF-8 ({e})'
    if not text.strip():
        return {}, 'empty'
    try:
        return json.loads(text), None
    except json.JSONDecodeError as e:
        head = p.read_bytes()[:32]
        hexpreview = ' '.join(f'{b:02x}' for b in head)
        asciipreview = ''.join(chr(b) if 32 <= b < 127 else '.' for b in head)
        return None, (
            f'invalid JSON at {e.lineno}:{e.colno}: {e.msg} '
            f'(first bytes: hex=[{hexpreview}] ascii="{asciipreview}")'
        )


def load_sources(paths):
    merged, used = {}, []
    any_error = False
    for p in paths:
        if not p.exists():
            print(f'skipping {p} (not found)', file=sys.stderr)
            continue
        data, err = _read_json_file(p)
        if data is None:
            print(f'skipping {p} ({err})', file=sys.stderr)
            any_error = True
            continue
        if err == 'empty':
            print(f'skipping {p} (empty)', file=sys.stderr)
            continue
        if not isinstance(data, dict):
            print(f'skipping {p} (not a JSON object)', file=sys.stderr)
            any_error = True
            continue
        for k, v in data.items():
            if k in merged and merged[k] != v:
                print(f'warning: {k!r} defined in multiple sources, later one wins',
                      file=sys.stderr)
            merged[k] = v
        used.append(p)
        print(f'loaded {p} ({len(data)} options)', file=sys.stderr)

    if not used:
        sys.exit(
            'no usable source files (all missing, empty, or invalid): '
            + ', '.join(str(p) for p in paths)
        )
    if any_error:
        print('warning: one or more sources failed to load; site may be incomplete.',
              file=sys.stderr)
    return merged, used


def documentation_coverage(options):
    total = len(options)
    if not total:
        return 0, 0, 0.0
    documented = sum(
        1 for v in options.values() if _has_visible_text(v.get('description'))
    )
    pct = math.floor(documented / total * 10000) / 100
    return documented, total, pct


def undocumented_options(options):
    return sorted(
        k for k, v in options.items() if not _has_visible_text(v.get('description'))
    )


def _fmt_pct(pct):
    if pct == int(pct):
        return f'{int(pct)}%'
    return f'{pct:.2f}%'


def render_coverage(documented, total, pct):
    if total == 0:
        return ''
    missing = total - documented
    cls = 'footer-coverage' + (' low' if missing else '')
    title = f'{documented}/{total} options documented'
    if missing:
        title += f' · {missing} missing'
    return (
        f'<div class="{cls}" title="{escape(title)}">'
        f'<span class="coverage-value">{_fmt_pct(pct)}</span> documented'
        f'</div>'
    )


def find_screenshot_dir(dirs):
    for d in dirs:
        if d.is_dir():
            return d
    return None


def collect_screenshots(src_dir, exts):
    return sorted(
        (p for p in src_dir.iterdir()
         if p.is_file() and p.suffix.lower() in exts),
        key=lambda p: p.name.lower(),
    )


def copy_screenshots(files, dst):
    dst.mkdir(parents=True, exist_ok=True)
    names = []
    for f in files:
        target = dst / f.name
        if not target.exists() or f.stat().st_mtime > target.stat().st_mtime:
            shutil.copy2(f, target)
        names.append(f.name)
    return names

def render_quick_start(config_text):
    if not config_text or not config_text.strip():
        return ''
    return (
        '<section class="quickstart-section" id="quickstart">'
        '<details class="quickstart">'
        '<summary>Quick start configuration</summary>'
        f'<pre><code>{escape(config_text.strip())}</code></pre>'
        '</details>'
        '</section>'
    )

def render_screenshots(names):
    if not names:
        return ''
    items = []
    for name in names:
        alt = Path(name).stem.replace('-', ' ').replace('_', ' ')
        items.append(
            '<figure class="screenshot">'
            f'<a href="screenshots/{escape(name)}" target="_blank" rel="noopener">'
            f'<img src="screenshots/{escape(name)}" alt="{escape(alt)}" loading="lazy">'
            '</a>'
            f'<figcaption>{escape(alt)}</figcaption>'
            '</figure>'
        )
    return (
        '<section class="screenshots-section" id="screenshots">'
        '<h2>Screenshots</h2>'
        '<div class="screenshots-grid">'
        + ''.join(items)
        + '</div></section>'
    )


def main():
    args = parse_args()
    cfg = load_config(args.config)

    dst = cfg["dst"]
    logo_src = cfg["logo"]
    logo_dst = dst.parent / "images" / "logo.png"
    screenshot_dst = dst.parent / "screenshots"

    data, used = load_sources(cfg["sources"])
    print(f'merged sources: {", ".join(str(p) for p in used)} ({len(data)} options)',
          file=sys.stderr)

    root = build_tree(data)
    top = sorted(root.children.values(), key=lambda n: n.name)
    content = ''.join(render_node(c, [c.name], 0) for c in top)
    sidebar = '<ul>' + ''.join(render_sidebar_item(c, [c.name]) for c in top) + '</ul>'

    documented, total, pct = documentation_coverage(data)
    coverage_html = render_coverage(documented, total, pct)
    print(f'documentation coverage: {documented}/{total} ({_fmt_pct(pct)})',
          file=sys.stderr)

    if documented < total:
        missing = undocumented_options(data)
        print(f'undocumented options ({len(missing)}):', file=sys.stderr)
        for name in missing[:30]:
            print(f'  {name}', file=sys.stderr)
        if len(missing) > 30:
            print(f'  …and {len(missing) - 30} more', file=sys.stderr)
    else:
        print('every option in the tree has a visible description.', file=sys.stderr)

    screenshots_html = ''
    screenshots_link = ''
    src_dir = find_screenshot_dir(cfg["screenshot_dirs"])
    if src_dir:
        files = collect_screenshots(src_dir, cfg["screenshot_exts"])
        if files:
            names = copy_screenshots(files, screenshot_dst)
            screenshots_html = render_screenshots(names)
            screenshots_link = (
                '<a href="#screenshots" class="screenshots-link">'
                f'Screenshots <span class="screenshots-count">({len(names)})</span>'
                '</a>'
            )
            print(f'bundled {len(names)} screenshot(s) from {src_dir}', file=sys.stderr)
        else:
            print(f'{src_dir}: no image files found', file=sys.stderr)
    else:
        print('no Screenshots/ or screenshots/ directory found', file=sys.stderr)

    built_at = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    quick_start_html = render_quick_start(cfg.get("quick_start_config", ""))
    quickstart_link = (
        '<a href="#quickstart" class="quickstart-link">Quick start</a>'
        if quick_start_html else ''
    )

    html = (TEMPLATE
            .replace('{STYLES}', STYLES)
            .replace('{SCRIPT}', SCRIPT)
            .replace('{PROJECT_NAME}', cfg['name'])
            .replace('{PROJECT_GITHUB}', cfg['github'])
            .replace('{CHANGELOG_URL}', cfg['changelog'])
            .replace('{PROJECT_URL}', cfg['url'])
            .replace('{PROJECT_URL_LABEL}', cfg['url_label'])
            .replace('{PROJECT_DESCRIPTION}', cfg['description'])
            .replace('{quickstart_link}', quickstart_link)
            .replace('{quick_start}', quick_start_html)
            .replace('{screenshots_link}', screenshots_link)
            .replace('{screenshots}', screenshots_html)
            .replace('{sidebar}', sidebar)
            .replace('{content}', content)
            .replace('{coverage}', coverage_html)
            .replace('{built_at}', f'built {built_at}'))

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(html, encoding='utf-8')

    if logo_src.exists():
        logo_dst.parent.mkdir(parents=True, exist_ok=True)
        if not logo_dst.exists() or logo_src.stat().st_mtime > logo_dst.stat().st_mtime:
            shutil.copy2(logo_src, logo_dst)
    else:
        print(f'warning: {logo_src} not found, logo will 404', file=sys.stderr)

    print(f'wrote {dst} ({len(html):,} bytes)', file=sys.stderr)


if __name__ == '__main__':
    main()
