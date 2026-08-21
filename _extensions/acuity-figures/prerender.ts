// Prerender every figures/<name>.fig.js for both formats. A figure exposes
// spec({document, width}) -> Observable Plot options, and may set staticFigure.
//
//   HTML         -> an {ojs} cell, interactive in the browser (Plot, d3 ambient)
//   Typst        -> the figure runs here, in Deno, drawn into JSDOM
//   staticFigure -> render the SVG once: inlined in HTML, the file in Typst
//
// Runs on Quarto's bundled Deno, so Quarto is the only dependency.

import * as Plot from "npm:@observablehq/plot";
import * as d3 from "npm:d3";
import * as yaml from "npm:js-yaml@4";
import { JSDOM } from "npm:jsdom@29";
import { json, relief } from "./runtime/_geo.js";

const projectDir = Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd();
const figuresDir = `${projectDir}/figures`;
const outDir = `${projectDir}/build/figures`;
const svgRef = (name: string) => `![](build/figures/svgs/${name}.svg){width=100%}\n`;

// Inline every file a figure loadText()s: a browser can't fetch _brand.yml,
// because Quarto doesn't publish _extensions/
const inlineLoadText = async (src: string) => {
  const paths = [...src.matchAll(/loadText\(\s*["'`]([^"'`]+)["'`]\s*\)/g)].map((m) => m[1]);
  const files = Object.fromEntries(await Promise.all(
    paths.map(async (p) => [p, await Deno.readTextFile(`${projectDir}/${p}`)]),
  ));
  return `const __files = ${JSON.stringify(files)};\n` +
    `const loadText = async (p) => __files[p];\n`;
};

// Build the interactive HTML cell. Plot and d3 are ambient in OJS; yaml comes
// from a CDN only when the source mentions it. Plot parses the opacity ramp's
// colour with d3, which cannot read the var(--fig-accent, …) form figures use
// in the browser, so resolve it against the live theme before plotting — the
// prerendered SVG bakes in the same accent, so the two formats agree.
//
// A legend makes Plot return a <figure> of two svgs, which misbehaves in the
// browser: the svgs paint their own white background (Quarto strips it only
// from bare svg outputs), and the fixed-width legend does not scale with the
// plot. Restack them into one svg, as the Typst path does, so the figure is
// one transparent block again
const htmlCell = async (src: string) => `{
${src.includes("yaml") ? `const yaml = await import("https://cdn.jsdelivr.net/npm/js-yaml@4/+esm");` : ""}
${await inlineLoadText(src)}${src}
const options = await spec({});
if (/^var\\(/.test(options.opacity?.color ?? "")) {
  const probe = document.body.appendChild(document.createElement("span"));
  probe.style.color = options.opacity.color;
  options.opacity = { ...options.opacity, color: getComputedStyle(probe).color };
  probe.remove();
}
const out = Plot.plot(options);
if (out.tagName !== "FIGURE" || [...out.children].some((c) => c.tagName !== "svg")) return out;
const root = document.createElementNS("http://www.w3.org/2000/svg", "svg");
let y = 0, w = 0;
for (const part of [...out.children]) {
  part.style.background = "none";
  part.setAttribute("overflow", "visible");
  part.setAttribute("y", y);
  y += Number(part.getAttribute("height"));
  w = Math.max(w, Number(part.getAttribute("width")));
  root.append(part);
}
root.setAttribute("width", w + ${2 * PAD});
root.setAttribute("height", y);
root.setAttribute("viewBox", ${-PAD} + " 0 " + (w + ${2 * PAD}) + " " + y);
root.style.cssText = "display:block;max-width:100%;height:auto";
return root;
}`;

const NS = "http://www.w3.org/2000/svg";
const STOPS = 16;
// Legend tick labels centre on the ramp's ends, so they poke past its box;
// the composed root leaves this much room either side instead of clipping
const PAD = 4;

// JSDOM has no 2D canvas, which Plot draws ramp legends into. Give every
// canvas a context that records the interpolated colours instead, one array
// per canvas, so the ramp can be rebuilt as a gradient
const shimCanvas = (document: any) => {
  const ramps: string[][] = [];
  const create = document.createElement.bind(document);
  document.createElement = (tag: string, ...rest: unknown[]) => {
    const el = create(tag, ...rest);
    if (tag === "canvas") {
      const colours: string[] = [];
      ramps.push(colours);
      el.getContext = () => ({
        set fillStyle(c: string) { colours.push(c); },
        fillRect() {},
      });
      el.toDataURL = () => "";
    }
    return el;
  };
  return ramps;
};

// Swap each ramp <image> (left empty by the shim) for a rect filled by a
// linearGradient sampled from the recorded colours: vector output, unlike the
// 256px raster Plot intended. The figure name keys the ids, so two figures on
// a page cannot collide
const swapRamps = (figure: any, ramps: string[][], name: string) => {
  const images = figure.querySelectorAll('image[preserveAspectRatio="none"][href=""]');
  [...images].forEach((image: any, i: number) => {
    const colours = ramps[i];
    if (!colours?.length) return;
    const doc = figure.ownerDocument;
    const id = `${name}-legend${i ? `-${i}` : ""}`;
    const gradient = doc.createElementNS(NS, "linearGradient");
    gradient.setAttribute("id", id);
    for (let k = 0; k < STOPS; k++) {
      // The colours are d3 interpolator output, rgb(…) or rgba(…). Not parsed
      // with d3.color, which reads any zero-alpha colour as NaN channels
      const colour = colours[Math.round((k * (colours.length - 1)) / (STOPS - 1))];
      const [r, g, b, a = 1] = (colour.match(/[\d.]+/g) ?? []).map(Number);
      const stop = doc.createElementNS(NS, "stop");
      stop.setAttribute("offset", `${(k * 100) / (STOPS - 1)}%`);
      stop.setAttribute("stop-color", `rgb(${r},${g},${b})`);
      stop.setAttribute("stop-opacity", `${a}`);
      gradient.append(stop);
    }
    const defs = doc.createElementNS(NS, "defs");
    defs.append(gradient);
    const rect = doc.createElementNS(NS, "rect");
    for (const a of ["x", "y", "width", "height"]) rect.setAttribute(a, image.getAttribute(a));
    rect.setAttribute("fill", `url(#${id})`);
    image.closest("svg").prepend(defs);
    image.replaceWith(rect);
  });
};

// With a legend on, Plot returns an HTML <figure>: legend svg(s) above the
// plot svg. Typst's image reader needs an <svg> root, so restack the parts as
// nested svgs in one composed root. An ordinal legend is a <div> of swatches,
// which no restacking can save
const composeFigure = (figure: any, name: string) => {
  const bad = [...figure.children].find((c: any) => c.tagName !== "svg");
  if (bad) {
    throw new Error(
      `figure "${name}": its <${bad.tagName.toLowerCase()}> legend cannot become an SVG; ` +
        `ordinal scales draw swatches — use legend: "ramp" or drop the legend`,
    );
  }
  const root = figure.ownerDocument.createElementNS(NS, "svg");
  let y = 0, w = 0;
  for (const part of [...figure.children]) {
    // Plot sets overflow: visible in a :where() rule SVG renderers skip, and a
    // nested svg clips by default, cutting the legend's last tick label
    part.setAttribute("overflow", "visible");
    part.setAttribute("y", `${y}`);
    y += Number(part.getAttribute("height"));
    w = Math.max(w, Number(part.getAttribute("width")));
    root.append(part);
  }
  root.setAttribute("width", `${w + 2 * PAD}`);
  root.setAttribute("height", `${y}`);
  root.setAttribute("viewBox", `${-PAD} 0 ${w + 2 * PAD} ${y}`);
  return root;
};

// Run the figure in this process and save its SVG. The figure has no imports:
// its free names are passed in, and the async wrapper allows top-level await
const writeSvg = async (name: string, src: string) => {
  const document = new JSDOM("").window.document;
  const ramps = shimCanvas(document);
  const loadText = (p: string) => Deno.readTextFile(`${projectDir}/${p}`);
  const spec = await new Function(
    "Plot", "d3", "yaml", "loadText", "json", "relief",
    `return (async () => { ${src}\n; return spec; })()`,
  )(Plot, d3, yaml, loadText, json, relief);

  let svg = Plot.plot(await spec({ document, width: 700 }));
  if (svg.tagName === "FIGURE") {
    swapRamps(svg, ramps, name);
    svg = composeFigure(svg, name);
  }
  svg.setAttribute("xmlns", NS);
  await Deno.writeTextFile(
    `${outDir}/svgs/${name}.svg`,
    '<?xml version="1.0" encoding="utf-8"?>\n' + svg.outerHTML,
  );
  // the inline copy scales with its container, as the file does through the
  // include's width=100%; background:none shields it from the white
  // background the browser-side Plot paints on every .plot-* figure
  svg.setAttribute("style", "display:block;width:100%;height:auto;background:none");
  return svg.outerHTML;
};

// Build the include Quarto stitches in: an OJS cell in HTML, the SVG in Typst.
// A static figure inlines its baked SVG in HTML, so page css can theme it
const include = async (name: string, src: string, svg: string) =>
  src.includes("staticFigure") ? `::: {.content-visible when-format="html"}
\`\`\`{=html}
${svg}
\`\`\`
:::

::: {.content-visible when-format="typst"}
${svgRef(name)}:::
` : `::: {.content-visible when-format="html"}
\`\`\`{ojs}
//| echo: false
${await htmlCell(src)}
\`\`\`
:::

::: {.content-visible when-format="typst"}
${svgRef(name)}:::
`;

// ── build ──────────────────────────────────────────────────────────────
// a project may use this format with no figures
if (!await Deno.stat(figuresDir).catch(() => null)) Deno.exit(0);
await Deno.mkdir(`${outDir}/svgs`, { recursive: true });

for await (const entry of Deno.readDir(figuresDir)) {
  if (!entry.name.endsWith(".fig.js")) continue;
  const name = entry.name.slice(0, -".fig.js".length);
  const src = await Deno.readTextFile(`${figuresDir}/${entry.name}`);
  const svg = await writeSvg(name, src);
  await Deno.writeTextFile(`${outDir}/${name}.qmd`, await include(name, src, svg));
}
