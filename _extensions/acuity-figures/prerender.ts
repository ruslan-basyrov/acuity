// Prerender every figures/<name>.fig.js for both formats. A figure exposes
// spec({document, width}) -> Observable Plot options, and may set staticFigure.
//
//   HTML         -> an {ojs} cell, interactive in the browser (Plot, d3 ambient)
//   Typst        -> the figure runs here, in Deno, drawn into JSDOM
//   staticFigure -> render the SVG once, show it in both formats
//
// Runs on Quarto's bundled Deno, so Quarto is the only dependency.

import * as Plot from "npm:@observablehq/plot";
import * as d3 from "npm:d3";
import * as yaml from "npm:js-yaml@4";
import { JSDOM } from "npm:jsdom";
import { json, relief } from "./runtime/_geo.js";

const projectDir = Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd();
const figuresDir = `${projectDir}/figures`;
const outDir = `${projectDir}/build/figures`;
const svgRef = (name: string) => `![](build/figures/svgs/${name}.svg)\n`;

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
// from a CDN only when the source mentions it
const htmlCell = async (src: string) => `{
${src.includes("yaml") ? `const yaml = await import("https://cdn.jsdelivr.net/npm/js-yaml@4/+esm");` : ""}
${await inlineLoadText(src)}${src}
return Plot.plot(await spec({}));
}`;

// Run the figure in this process and save its SVG. The figure has no imports:
// its free names are passed in, and the async wrapper allows top-level await
const writeSvg = async (name: string, src: string) => {
  const document = new JSDOM("").window.document;
  const loadText = (p: string) => Deno.readTextFile(`${projectDir}/${p}`);
  const spec = await new Function(
    "Plot", "d3", "yaml", "loadText", "json", "relief",
    `return (async () => { ${src}\n; return spec; })()`,
  )(Plot, d3, yaml, loadText, json, relief);

  const svg = Plot.plot(await spec({ document, width: 700 }));
  svg.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  await Deno.writeTextFile(
    `${outDir}/svgs/${name}.svg`,
    '<?xml version="1.0" encoding="utf-8"?>\n' + svg.outerHTML,
  );
};

// Build the include Quarto stitches in: an OJS cell in HTML, the SVG in Typst,
// or the SVG in both for a static figure
const include = async (name: string, src: string) =>
  src.includes("staticFigure") ? svgRef(name) : `::: {.content-visible when-format="html"}
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
  await Deno.writeTextFile(`${outDir}/${name}.qmd`, await include(name, src));
  await writeSvg(name, src);
}
