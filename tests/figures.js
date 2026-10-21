// Exercise real figure modules with changed settings, without another test dependency.
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url)).replace(/\/$/, "");
const names = ["histogram", "groups", "sequential", "diverging", "threshold", "symbol", "opacity", "palette", "intensity"];
const config = {
  root, html: false, small: 0.8,
  settings: { aspectRatio: 2.4, minHeight: 8, legendWidth: 12 },
  theme: {
    font: "sans-serif", ink: "#222222", accent: "#bb4422", paper: "#ffffff",
    palette: { blue: "#332288", cyan: "#88ccee", teal: "#44aa99" },
    categorical: ["#332288", "#88ccee", "#44aa99"],
  },
  figures: names.map((name) => ({ module: `${root}/figures/${name}.fig.js`, width: 24 })),
};
config.figures.push({ module: `${root}/figures/histogram.fig.js`, width: 6 });

async function render(settings) {
  const child = new Deno.Command(Deno.execPath(), {
    args: ["run", "--allow-all", `${root}/_extensions/acuity/figures.js`],
    stdin: "piped", stdout: "piped", stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(JSON.stringify(settings)));
  await writer.close();
  const result = await child.output();
  assert.equal(result.code, 0, new TextDecoder().decode(result.stderr));
  return JSON.parse(new TextDecoder().decode(result.stdout)).map(({ svg }) => svg);
}

const original = await render(config);
const changed = await render({ ...config, html: true, small: 1, settings: { ...config.settings, aspectRatio: 3, legendWidth: 8 } });
assert.equal(original.length, config.figures.length);
const box = (svg) => svg.match(/viewBox="([^"]+)"/)[1].split(" ").map(Number);
assert.equal(box(original[0])[3], 24 * 16 / 2.4, "default aspect ratio sets chart height");
assert.equal(box(changed[0])[3], 24 * 16 / 3, "changing the ratio changes chart height");
assert.deepEqual(box(original[7]), box(changed[7]), "explicit figure height is preserved");
assert.equal(box(original.at(-1))[3], 8 * 16, "minimum height keeps narrow figures readable");
assert.match(original[1], /#332288/, "categories use the supplied palette");
assert.match(original[2], /linearGradient/, "continuous legend is SVG");
assert.match(original[4], /<stop offset="0\.2"/, "threshold legend retains its bands");
assert.match(original[6], /stop-opacity="0"/, "opacity legend starts transparent");

for (const [output, size] of [[original, "12.8px"], [changed, "16px"]]) {
  for (const svg of output) {
    assert.match(svg, /^<svg\b/);
    assert.doesNotMatch(svg, /<(?:canvas|foreignObject|div)\b|NaN|Infinity/);
    assert.ok(svg.includes(`font-size: ${size}`), "shared small text reaches every figure");
  }
  const ids = [...output.join("").matchAll(/id="(acuity-legend-[^"]+)"/g)].map((match) => match[1]);
  assert.equal(ids.length, new Set(ids).size, "legends have distinct gradient IDs");
}
console.log("Figure checks passed: shared sizing, overrides, palettes, and SVG legends.");
