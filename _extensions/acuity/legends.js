// Plot's legends can contain HTML or canvas. These SVG-only legends also work in Typst.
export const categorical = (scale) => ["ordinal", "categorical", "point", "band"].includes(scale?.type);

export function element(parent, name, attributes = {}, text) {
  const node = parent.ownerDocument.createElementNS("http://www.w3.org/2000/svg", name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
  if (text != null) node.textContent = text;
  parent.append(node);
  return node;
}

const spacing = { line: 1.4, swatch: 0.75, gap: 0.35 };
// Estimate text width without a browser or native font-measurement dependency.
const measure = (label) => Array.from(String(label)).reduce((width, c) =>
  width + (/[ ijlrtfI.,:;'|!]/.test(c) ? 0.3 : /[mwMW]/.test(c) ? 0.82 : /[A-Z]/.test(c) ? 0.66 : 0.55), 0);

function label(parent, x, y, size, text, anchor = "start") {
  element(parent, "text", { x, y: y + 0.35 * size, "text-anchor": anchor }, text);
}

function swatches(parent, scale, options) {
  const { size, width, color, d3 } = options;
  let x = 0, y = spacing.line * size / 2;
  function place(ems) {
    if (x > 0 && x + ems * size > width) { x = 0; y += spacing.line * size; }
    const start = x;
    x += (ems + 1) * size;
    return start;
  }
  if (options.label != null) label(parent, place(measure(options.label)), y, size, options.label);
  for (const value of scale.domain) {
    const start = place(spacing.swatch + spacing.gap + measure(value));
    const side = spacing.swatch * size;
    if (typeof scale.apply(value)?.draw === "function") {
      element(parent, "path", {
        transform: `translate(${start + side / 2},${y})`,
        d: d3.symbol(scale.apply(value), side ** 2 / 2)(),
        fill: "none", stroke: color?.domain.includes(value) ? color.apply(value) : "currentColor",
        "stroke-width": 1.5,
      });
    } else {
      element(parent, "rect", { x: start, y: y - side / 2, width: side, height: side, fill: scale.apply(value) });
    }
    label(parent, start + (spacing.swatch + spacing.gap) * size, y, size, value);
  }
  return y + spacing.line * size / 2;
}

function ramp(parent, scale, options) {
  const { size, d3, faded } = options;
  const width = Math.min(options.width, options.rampWidth);
  let y = 0;
  if (options.label != null) {
    label(parent, 0, spacing.line * size / 2, size, options.label);
    y = spacing.line * size;
  }
  let stops, ticks;
  if (scale.range?.length === scale.domain.length + 1) {
    const count = scale.range.length;
    stops = scale.range.flatMap((color, i) => [[i / count, color], [(i + 1) / count, color]]);
    ticks = scale.domain.map((value, i) => [(i + 1) / count, String(value)]);
  } else {
    const scales = { log: d3.scaleLog, sqrt: d3.scaleSqrt, symlog: d3.scaleSymlog };
    const position = (scales[scale.type] ?? d3.scaleLinear)().domain(d3.extent(scale.domain));
    const format = position.tickFormat(4);
    stops = Array.from({ length: 11 }, (_, i) => {
      const value = scale.apply(position.invert(i / 10));
      return faded ? [i / 10, faded, value] : [i / 10, value];
    });
    ticks = position.ticks(4).map((value) => [position(value), format(value)]);
  }
  const gradient = element(element(parent, "defs"), "linearGradient", { id: options.id });
  for (const [offset, color, opacity = 1] of stops) {
    element(gradient, "stop", { offset, "stop-color": color, "stop-opacity": opacity });
  }
  element(parent, "rect", { y, width, height: 0.6 * size, fill: `url(#${options.id})` });
  y += (0.6 + spacing.line / 2) * size;
  for (const [at, name] of ticks) label(parent, at * width, y, size, name, at < 0.05 ? "start" : at > 0.95 ? "end" : "middle");
  return y + spacing.line * size / 2;
}

export function drawLegend(parent, scale, options) {
  return (categorical(scale) ? swatches : ramp)(parent, scale, options) + 0.8 * options.size;
}
