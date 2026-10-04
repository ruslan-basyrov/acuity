// Mark helpers, passed to every figure by prerender.ts.

import * as Plot from "npm:@observablehq/plot";

export const zeroLine = () =>
  Plot.ruleY([0], { stroke: "currentColor", strokeOpacity: 0.75, strokeWidth: 1 });

export const contextLines = (rows, opts) =>
  Plot.lineY(rows, { stroke: "currentColor", strokeOpacity: 0.3, strokeWidth: 1, ...opts });

export const endLabel = (rows, opts) =>
  Plot.text(rows, { textAnchor: "start", dx: 8, ...opts });
