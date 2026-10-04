// Prerender every figures/<name>.fig.js to one SVG. A figure's default export
// takes { Plot, d3, json, relief, document, width, brand, theme } and returns
// Observable Plot options. HTML inlines the SVG with the theme() colours as CSS
// variables, so they follow the page theme.
//
// Runs on Quarto's bundled Deno, so Quarto is the only dependency.

import * as Plot from "npm:@observablehq/plot";
import * as d3 from "npm:d3";
import * as yaml from "npm:js-yaml@4";
import { JSDOM } from "npm:jsdom@29";
import * as geo from "./runtime/_geo.js";

const projectDir = Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd();
const figuresDir = `${projectDir}/figures`;
const outDir = `${projectDir}/build/figures`;
const brand: any = yaml.load(await Deno.readTextFile(new URL("../acuity/_brand.yml", import.meta.url)));
const p = brand.color.palette;
// role -> [CSS variable, light colour]
const ROLES: Record<string, [string, string]> = {
  accent: ["--fig-accent", brand.color.primary.light],
  slot1: ["--fig-slot1", p.blue],
  slot2: ["--fig-slot2", p.purple],
  slot3: ["--fig-slot3", p.olive],
  paper: ["--bs-body-bg", p.white],
};

const themed = (svg: string, roles: Set<string>) =>
  [...roles].reduce((s, role) => {
    const [name, hex] = ROLES[role];
    return s.replace(new RegExp(`"${hex}"`, "gi"), `"var(${name}, ${hex})"`);
  }, svg);

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
      stop.setAttribute("stop-color", d3.rgb(r, g, b).formatHex());
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

// Writes <name>.svg for Typst and <name>.html, themed, for HTML; figure.lua
// places them
const render = async (name: string, figure: (context: any) => any) => {
  const document = new JSDOM("").window.document;
  const ramps = shimCanvas(document);
  const used = new Set<string>();
  const theme = (role: string) => (used.add(role), ROLES[role][1]);
  const context = { Plot, d3, ...geo, document, width: 700, brand, theme };

  let svg = Plot.plot(await figure(context));
  if (svg.tagName === "FIGURE") {
    swapRamps(svg, ramps, name);
    svg = composeFigure(svg, name);
  }
  svg.setAttribute("xmlns", NS);
  await Deno.writeTextFile(
    `${outDir}/${name}.svg`,
    '<?xml version="1.0" encoding="utf-8"?>\n' + svg.outerHTML,
  );
  // background:none shields it from the white background Plot's CSS paints
  svg.setAttribute("style", "display:block;width:100%;height:auto;background:none");
  await Deno.writeTextFile(`${outDir}/${name}.html`, themed(svg.outerHTML, used));
};

// ── build ──────────────────────────────────────────────────────────────
// a project may use this format with no figures
if (!await Deno.stat(figuresDir).catch(() => null)) Deno.exit(0);
await Deno.mkdir(outDir, { recursive: true });

for await (const entry of Deno.readDir(figuresDir)) {
  if (!entry.name.endsWith(".fig.js")) continue;
  const { default: figure } = await import(`${figuresDir}/${entry.name}`);
  await render(entry.name.slice(0, -".fig.js".length), figure);
}
