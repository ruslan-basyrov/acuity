// The points' groups, as a symbol and a colour. Its legend draws each
// group's symbol in its colour.

import points from "./points.js";

export default ({ Plot, d3 }) => ({
  symbol: { legend: true },
  marks: [Plot.dot(points(d3), { x: "x", y: "y", symbol: "group", stroke: "group" })],
});
