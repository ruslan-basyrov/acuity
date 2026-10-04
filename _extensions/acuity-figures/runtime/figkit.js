// Prepended to every figures/*.fig.js by prerender.ts.

const zeroLine = () =>
  Plot.ruleY([0], { stroke: "currentColor", strokeOpacity: 0.75, strokeWidth: 1 });

const contextLines = (rows, opts) =>
  Plot.lineY(rows, { stroke: "currentColor", strokeOpacity: 0.3, strokeWidth: 1, ...opts });

const endLabel = (rows, opts) =>
  Plot.text(rows, { textAnchor: "start", dx: 8, ...opts });
