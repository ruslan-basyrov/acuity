// One batch per document. Quarto supplies Deno; these are the only npm dependencies.
import * as Plot from "npm:@observablehq/plot@0.6.17";
import * as d3 from "npm:d3@7.9.0";
import { JSDOM } from "npm:jsdom@29.1.1";
import { pathToFileURL } from "node:url";
import { categorical, drawLegend, element } from "./legends.js";

const em = 16; // SVG coordinates per body em; output sizing is handled by Lua/CSS.
const document = new JSDOM("").window.document;

async function render(figure, config, index) {
  const { html, small, settings, theme } = config;
  const width = figure.width * em;
  const { default: build } = await import(pathToFileURL(figure.module).href);
  const options = await build({
    Plot, d3, theme, width, em,
    read: (path) => Deno.readTextFileSync(`${config.root}/${path}`),
  });
  const legends = ["color", "opacity", "symbol"].filter((name) => options[name]?.legend);
  const scales = Object.fromEntries(legends.map((name) => [name, { ...options[name], legend: false }]));
  const draw = (color = scales.color ?? options.color) => Plot.plot({
    height: Math.max(width / settings.aspectRatio, settings.minHeight * em),
    ...options,
    ...scales,
    color,
    width,
    // Avoid font fallback for arrow glyphs missing from the body face.
    x: { labelArrow: false, ...options.x },
    y: { labelArrow: false, ...options.y },
    style: {
      fontFamily: theme.font, fontSize: `${small * em}px`,
      ...(html ? { width: "100%", maxWidth: `${figure.width}rem`, height: "auto" } : { color: theme.ink }),
      ...options.style,
    },
    document,
  });
  let svg = draw();
  const ownColors = ["range", "scheme", "interpolate"].some((key) => options.color?.[key] !== undefined);
  if (!ownColors && categorical(svg.scale("color"))) {
    svg = draw({ ...options.color, range: theme.categorical, legend: false });
  }
  svg.setAttribute("xmlns", "http://www.w3.org/2000/svg");

  // Insert legends above the marks; their text uses the same size as captions.
  const marks = Array.from(svg.children).filter((child) => child.localName !== "style");
  let top = 0;
  for (const name of legends.filter((name) => svg.scale(name))) {
    const group = element(svg, "g", { transform: `translate(0,${top})`, "text-anchor": "start" });
    top += drawLegend(group, svg.scale(name), {
      d3, width, size: small * em, label: options[name].label,
      rampWidth: settings.legendWidth * em, id: `acuity-legend-${index}-${name}`,
      faded: name === "opacity" ? options.opacity.color ?? theme.ink : undefined,
      color: svg.scale("color"),
    });
  }
  if (top > 0) {
    element(svg, "g", { transform: `translate(0,${top})` }).append(...marks);
    const height = Number(svg.getAttribute("height")) + top;
    svg.setAttribute("height", height);
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  }
  return { svg: svg.outerHTML };
}

const config = JSON.parse(await new Response(Deno.stdin.readable).text());
// YAML maps have no guaranteed order after passing through Lua.
config.theme.palette = Object.fromEntries(Object.entries(config.theme.palette).sort(([a], [b]) => a.localeCompare(b)));
const drawn = [];
for (const [index, figure] of config.figures.entries()) drawn.push(await render(figure, config, index));
console.log(JSON.stringify(drawn));
