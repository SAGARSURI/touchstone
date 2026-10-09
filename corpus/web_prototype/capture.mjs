// A14 prototype: captures schema v1 snapshots from web pages (spec,
// Assumption register: "Map it onto DOM, computed style and the
// accessibility tree; prototype 5 fixture screens on web").
//
//   node capture.mjs            writes snapshots/<screen>.snapshot and out/report.json
//
// Components are elements with data-component (and data-key for an explicit
// key), the web counterpart of widget classes declared in the app. The output
// uses the same canonical form and hashing as the Flutter capture, so
// package:touchstone's Snapshot.parse reads it (test/web_schema_test.dart).

import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const screens = ['text', 'decorated', 'effects', 'lists', 'overlay'];
const library = JSON.parse(readFileSync(join(here, 'package.json'), 'utf8')).name;

const sha = (s) => createHash('sha256').update(s).digest('hex');
// Dart's double.toString: shortest round trip, integers with ".0".
const d = (n) => (Number.isInteger(n) ? `${n}.0` : `${n}`);
const json = (v) => JSON.stringify(v);
const pairs = (m) => Object.entries(m).map(([k, v]) => `${k}=${json(v)}`).join('\t');

/// Runs in the page: the component tree, each component's own paint text,
/// bounds and style, and the element-to-component map for semantics.
function extract() {
  const PAINT = [
    'display', 'visibility', 'opacity', 'color', 'background-color', 'background-image', 'background-size',
    'background-position', 'background-repeat', 'background-clip', 'border-top-width', 'border-right-width',
    'border-bottom-width', 'border-left-width', 'border-top-style', 'border-right-style', 'border-bottom-style',
    'border-left-style', 'border-top-color', 'border-right-color', 'border-bottom-color', 'border-left-color',
    'border-top-left-radius', 'border-top-right-radius', 'border-bottom-right-radius', 'border-bottom-left-radius',
    'outline-width', 'outline-style', 'outline-color', 'box-shadow', 'text-shadow', 'transform', 'transform-origin',
    'filter', 'backdrop-filter', 'clip-path', 'mask-image', '-webkit-mask-image', 'mix-blend-mode', 'isolation',
    'overflow-x', 'overflow-y', 'z-index', 'position', 'font-family', 'font-size', 'font-weight', 'font-style',
    'letter-spacing', 'word-spacing', 'line-height', 'text-decoration-line', 'text-decoration-color',
    'text-decoration-style', 'text-transform', 'text-overflow', 'white-space', '-webkit-line-clamp', 'object-fit',
    'object-position', 'content',
  ];
  const DEFAULTS = new Map();
  const probe = document.createElement('div');
  document.body.appendChild(probe);
  const ps = getComputedStyle(probe);
  for (const p of PAINT) DEFAULTS.set(p, ps.getPropertyValue(p));
  probe.remove();

  const root = { type: 'root', key: null, el: document.documentElement, children: [], idx: 0 };
  const comps = [root];
  const ownerOf = new Map();
  (function walk(el, owner) {
    let me = owner;
    if (el.dataset && el.dataset.component) {
      me = { type: el.dataset.component, key: el.dataset.key ?? null, el, children: [], idx: comps.length, parent: owner };
      comps.push(me);
      owner.children.push(me);
    }
    ownerOf.set(el, me);
    el.setAttribute('data-ts-owner', String(me.idx));
    for (const child of el.children) walk(child, me);
  })(document.documentElement, root);

  const rectOf = (el) => (el === document.documentElement ? new DOMRect(0, 0, innerWidth, innerHeight) : el.getBoundingClientRect());
  const style = (el, pseudo) => {
    const cs = getComputedStyle(el, pseudo);
    const out = {};
    for (const p of PAINT) {
      const v = cs.getPropertyValue(p);
      if (v !== DEFAULTS.get(p)) out[p] = v;
    }
    return out;
  };
  const r4 = (r, o) => [r.x - o.x, r.y - o.y, r.width, r.height];
  const painted = new Set();

  // Paint text: owned elements and text runs in document order, positions
  // relative to the component's own box; child components leave a marker.
  // The flattened paint walks through child components as if they were part
  // of this one.
  const paintOps = (c, flat) => {
    const origin = rectOf(c.el);
    const ops = [];
    const visit = (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        if (!node.textContent.trim()) return;
        const range = document.createRange();
        range.selectNodeContents(node);
        const rects = [...range.getClientRects()].map((r) => r4(r, origin));
        if (rects.length) {
          ops.push(['text', node.textContent, rects]);
          painted.add(c);
        }
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (!flat && node !== c.el && ownerOf.get(node) !== c) {
        ops.push(['comp', ownerOf.get(node).idx]);
        return;
      }
      const cs = getComputedStyle(node);
      if (cs.display === 'none') return;
      const rect = node === document.documentElement ? null : node.getBoundingClientRect();
      const own = style(node);
      const op = ['el', node.localName, rect ? r4(rect, origin) : null, own];
      for (const pseudo of ['::before', '::after']) {
        const ps = getComputedStyle(node, pseudo);
        if (ps.content && ps.content !== 'none' && ps.content !== 'normal') op.push([pseudo, style(node, pseudo)]);
      }
      if (node.localName === 'img') op.push(['src', node.currentSrc, node.naturalWidth, node.naturalHeight]);
      if (node.localName === 'canvas') op.push(['canvas', node.width, node.height]);
      ops.push(op);
      if (rect && rect.width * rect.height > 0 && cs.visibility === 'visible') {
        const visual = Object.keys(own).some((k) => /background|border|shadow|outline/.test(k));
        if (visual || node.localName === 'canvas' || node.localName === 'img') painted.add(c);
      }
      for (const child of node.childNodes) visit(child);
      ops.push(['end']);
    };
    visit(c.el);
    return ops;
  };
  for (const c of comps) {
    c.ops = paintOps(c, false);
    c.flatOps = paintOps(c, true);
    c.bounds = c === root ? [0, 0, innerWidth, innerHeight] : (({ x, y, width, height }) => [x, y, width, height])(rectOf(c.el));
    c.canvas = c.el.localName === 'canvas' || !!c.el.querySelector?.(`canvas[data-ts-owner="${c.idx}"]`);
    c.styleOf = style(c.el);
  }
  return {
    comps: comps.map((c) => ({
      idx: c.idx,
      type: c.type,
      key: c.key,
      parent: c.parent ? c.parent.idx : null,
      children: c.children.map((x) => x.idx),
      ops: c.ops,
      flatOps: c.flatOps,
      bounds: c.bounds,
      painted: painted.has(c),
      canvas: c.canvas,
      style: c.styleOf,
    })),
    inputs: {
      viewport: `${innerWidth}.0x${innerHeight}.0@${devicePixelRatio}${Number.isInteger(devicePixelRatio) ? '.0' : ''}`,
      platform: navigator.platform,
      locale: document.documentElement.lang || navigator.language,
      // The user's text size: the browser's medium font size against its 16px default.
      textScale: (() => {
        const p = document.createElement('span');
        p.style.font = 'medium sans-serif';
        document.body.appendChild(p);
        const scale = parseFloat(getComputedStyle(p).fontSize) / 16;
        p.remove();
        return `${scale}${Number.isInteger(scale) ? '.0' : ''}`;
      })(),
      brightness: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
      theme: '-',
      state: '-',
    },
  };
}

/// Semantics from the accessibility tree, grouped by owning component. The
/// map's `ordered` list keeps every entry with its owner in tree order.
async function semantics(cdp) {
  const { root } = await cdp.send('DOM.getDocument', { depth: -1, pierce: true });
  const owner = new Map();
  (function walk(n, inherited) {
    let own = inherited;
    const a = n.attributes ?? [];
    const i = a.indexOf('data-ts-owner');
    if (i >= 0) own = Number(a[i + 1]);
    owner.set(n.backendNodeId, own);
    for (const c of n.children ?? []) walk(c, own);
  })(root, 0);
  const { nodes } = await cdp.send('Accessibility.getFullAXTree');
  const out = new Map();
  out.ordered = [];
  for (const n of nodes) {
    if (n.ignored || n.backendDOMNodeId === undefined) continue;
    const role = n.role?.value;
    if (role === 'none' || role === 'generic' || role === 'InlineTextBox') continue;
    const entry = { role };
    for (const f of ['name', 'value', 'description']) {
      if (n[f]?.value !== undefined && n[f].value !== '') entry[f] = String(n[f].value);
    }
    // The document URL is where the file happens to be, not part of the UI.
    for (const p of n.properties ?? []) if (p.name !== 'url') entry[p.name] = p.value.value;
    const comp = owner.get(n.backendDOMNodeId) ?? 0;
    if (!out.has(comp)) out.set(comp, []);
    out.get(comp).push(entry);
    out.ordered.push([comp, entry]);
  }
  return out;
}

async function fonts(cdp) {
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  const { root } = await cdp.send('DOM.getDocument', { depth: -1 });
  const used = new Set();
  const texts = [];
  (function walk(n) {
    if (n.nodeType === 1 && (n.children ?? []).some((c) => c.nodeType === 3 && c.nodeValue.trim())) texts.push(n.nodeId);
    for (const c of n.children ?? []) walk(c);
  })(root);
  for (const nodeId of texts) {
    const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
    for (const f of fonts) used.add(`${f.familyName}/${f.postScriptName}`);
  }
  return [...used].sort();
}

async function capture(browser, screen, mutate) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, locale: 'en-US' });
  const page = await context.newPage();
  await page.goto(pathToFileURL(join(here, 'screens', `${screen}.html`)).href);
  await page.evaluate(() => document.fonts.ready);
  if (mutate) await page.evaluate(mutate);
  const cdp = await context.newCDPSession(page);
  const data = await page.evaluate(extract);
  const sem = await semantics(cdp);
  const fontList = await fonts(cdp);
  const pixels = sha(await page.screenshot());

  // Prune components that paint nothing and own no semantics, then name them.
  const byIdx = new Map(data.comps.map((c) => [c.idx, c]));
  const shown = new Set();
  for (const c of [...data.comps].reverse()) {
    if (c.idx === 0 || c.painted || sem.has(c.idx) || c.children.some((k) => shown.has(k))) shown.add(c.idx);
  }
  const segment = new Map([[0, 'root']]);
  const name = (c) => {
    const counts = new Map();
    for (const k of c.children.filter((k) => shown.has(k))) {
      const child = byIdx.get(k);
      let s;
      if (child.key !== null) s = `${child.type}#${child.key}`;
      else {
        const n = counts.get(child.type) ?? 0;
        counts.set(child.type, n + 1);
        s = `${child.type}@${n}`;
      }
      segment.set(k, s);
      name(child);
    }
  };
  name(byIdx.get(0));
  const fullId = (idx) => (idx === 0 ? 'root' : `${fullId(byIdx.get(idx).parent)}/${segment.get(idx)}`);

  const opaqueNodes = {};
  const pixelsOf = new Map();
  const subtree = (c) => [c.idx, ...c.children.filter((k) => shown.has(k)).flatMap((k) => subtree(byIdx.get(k)))];
  const build = async (c) => {
    const ops = c.ops.map((op) => (op[0] === 'comp' ? ['comp', segment.get(op[1]) ?? '-'] : op));
    let paintText = json(ops);
    const reasons = [];
    if (c.canvas) {
      // Script-drawn pixels: the paint is a pixel hash, as for a CustomPainter that cannot be recorded.
      reasons.push('canvas');
      const el = await page.$(`[data-ts-owner="${c.idx}"]`);
      pixelsOf.set(c.idx, sha(await el.screenshot()));
      paintText += `px(${pixelsOf.get(c.idx)})`;
    }
    if (reasons.length) opaqueNodes[fullId(c.idx)] = reasons;
    const children = [];
    for (const k of c.children.filter((k) => shown.has(k))) children.push(await build(byIdx.get(k)));
    // The subtree's output with component boundaries removed (schema: flat).
    const inside = new Set(subtree(c));
    const flatText = json(c.flatOps) + [...inside].map((k) => (pixelsOf.has(k) ? `px(${pixelsOf.get(k)})` : '')).join('');
    const flatSem = sem.ordered.filter(([k]) => inside.has(k)).map(([, e]) => e);
    const node = {
      id: segment.get(c.idx),
      bounds: c.bounds.map(d).join(','),
      paint: sha(paintText),
      sem: json(sem.get(c.idx) ?? []),
      opaque: reasons.length ? reasons.join('+') : '-',
      flat: sha(`${flatText}\n${json(flatSem)}`),
      type: c.idx === 0 ? 'root' : `${c.type} (${screen}.html)`,
      style: json(c.style),
      children,
    };
    const detection = [json(node.id), node.bounds, node.paint, node.sem, node.opaque, node.flat].join('\t');
    node.sub = sha([detection, ...children.map((x) => x.sub)].join('\n'));
    return node;
  };
  const root = await build(byIdx.get(0));
  const toolchain = {
    browser: `chromium ${browser.version()}`,
    engine: 'blink',
    renderer: 'skia-software',
    library: library,
    fonts: sha(fontList.join(',')).slice(0, 16),
  };
  const lines = [
    'touchstone-snapshot 1',
    `id\t${json(`web/${screen}`)}`,
    `inputs\t${pairs(data.inputs)}`,
    `toolchain\t${pairs(toolchain)}`,
    `limit\t${json('web: script-drawn canvas pixels are hashed; cross-origin frames are not captured')}`,
    ...Object.entries(opaqueNodes).map(([k, v]) => `opaque\t${json(k)}\t${v.join('+')}`),
    `rootHash\t${root.sub}`,
    'nodes',
  ];
  const write = (n, depth) => {
    lines.push(`${'  '.repeat(depth)}${[json(n.id), `bounds=${n.bounds}`, `paint=${n.paint}`, `sem=${n.sem}`,
      `opaque=${n.opaque}`, `flat=${n.flat}`, `type=${json(n.type)}`, `style=${n.style}`, `sub=${n.sub}`].join('\t')}`);
    n.children.forEach((c) => write(c, depth + 1));
  };
  write(root, 0);
  await context.close();
  return { text: `${lines.join('\n')}\n`, root, pixels, fonts: fontList };
}

/// One mutation per fixture kind the screen exercises, mirroring the
/// fixture app's mutations, and the node each should change.
const mutations = {
  text: [
    ['text content', 'heading', () => { document.querySelector('[data-key=heading]').textContent = 'Order summery'; }],
    ['font weight', 'heading', () => { document.querySelector('[data-key=heading]').style.fontWeight = '400'; }],
    ['span colour', 'rich', () => { document.querySelector('.money').style.color = '#1565c1'; }],
  ],
  decorated: [
    ['colour token', 'box', () => { document.documentElement.style.setProperty('--box', '#4caf51'); }],
    ['corner radius', 'box', () => { document.querySelector('.box').style.borderRadius = '13px'; }],
    ['gradient stop', 'gradient', () => { document.querySelector('.gradient').style.background = 'linear-gradient(to right, #90caf9 0%, #0d47a1 61%)'; }],
  ],
  effects: [
    ['opacity', 'opacity', () => { document.querySelector('.opacity').style.opacity = '0.6'; }],
    ['clip radius', 'clip', () => { document.querySelector('.clip').style.borderRadius = '17px'; }],
    ['paint order', 'order', () => { const o = document.querySelector('.order'); o.appendChild(o.firstElementChild); }],
    ['canvas output', 'canvas', () => { const x = document.querySelector('canvas').getContext('2d'); x.fillRect(0, 0, 1, 1); }],
  ],
  lists: [
    ['row colour', 'row0', () => { document.querySelector('[data-key=row0]').style.background = '#fafafb'; }],
    ['title', 'title', () => { document.querySelector('[data-key=title]').textContent = 'Watchlists'; }],
  ],
  overlay: [
    ['scrim opacity', 'scrim', () => { document.documentElement.style.setProperty('--scrim', 'rgba(0, 0, 0, 0.545)'); }],
    ['sheet height', 'sheet', () => { document.querySelector('.sheet').style.height = '161px'; }],
    ['dialog label', 'dialog', () => { document.getElementById('t').textContent = 'Delete orders?'; }],
  ],
};

const browser = await chromium.launch({ args: ['--disable-gpu', '--font-render-hinting=none'] });
mkdirSync(join(here, 'snapshots'), { recursive: true });
mkdirSync(join(here, 'out'), { recursive: true });
const report = [];
const flat = (n, prefix = '') => {
  const id = prefix ? `${prefix}/${n.id}` : n.id;
  return [[id, n], ...n.children.flatMap((c) => flat(c, id))];
};
for (const screen of screens) {
  const base = await capture(browser, screen);
  const again = await capture(browser, screen);
  writeFileSync(join(here, 'snapshots', `${screen}.snapshot`), base.text);
  const nodes = flat(base.root);
  const missing = [];
  for (const [id, n] of nodes) {
    for (const f of ['id', 'bounds', 'paint', 'sem', 'opaque', 'type', 'style', 'sub']) {
      if (n[f] === undefined || n[f] === '') missing.push(`${id}.${f}`);
    }
  }
  const results = [];
  for (const [label, key, fn] of mutations[screen]) {
    const m = await capture(browser, screen, fn);
    const before = new Map(flat(base.root).map(([id, n]) => [id, n]));
    const changed = flat(m.root)
      .filter(([id, n]) => !before.has(id) || before.get(id).paint !== n.paint || before.get(id).bounds !== n.bounds || before.get(id).sem !== n.sem)
      .map(([id]) => id);
    results.push({
      mutation: label,
      pixelsChanged: m.pixels !== base.pixels,
      snapshotChanged: m.root.sub !== base.root.sub,
      expectedNodeChanged: changed.some((id) => id.endsWith(`Tagged#${key}`)),
      changed,
    });
  }
  report.push({
    screen,
    nodes: nodes.length,
    repeatIdentical: base.text === again.text,
    missingFields: missing,
    fonts: base.fonts,
    mutations: results,
  });
}
await browser.close();
writeFileSync(join(here, 'out', 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
for (const r of report) {
  console.log(`${r.screen}: ${r.nodes} nodes, repeat identical ${r.repeatIdentical}, missing fields ${r.missingFields.length}`);
  for (const m of r.mutations) {
    console.log(`  ${m.mutation}: pixels ${m.pixelsChanged}, snapshot ${m.snapshotChanged}, on expected node ${m.expectedNodeChanged}`);
  }
}
