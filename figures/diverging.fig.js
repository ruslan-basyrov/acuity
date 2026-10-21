// The product of each point's coordinates, as a diverging colour centred on
// zero. Its legend is a ramp.

import points from "./points.js";

export default ({ Plot, d3 }) => ({
  color: { legend: true, type: "diverging", scheme: "BuRd", label: "x · y" },
  marks: [Plot.dot(points(d3), { x: "x", y: "y", fill: (d) => d.x * d.y })],
});
