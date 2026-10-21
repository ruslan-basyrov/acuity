// How far each point lies from the centre, as a sequential colour. Its legend
// is a ramp.

import points from "./points.js";

export default ({ Plot, d3 }) => ({
  color: { legend: true, scheme: "viridis", label: "Distance from centre" },
  marks: [Plot.dot(points(d3), { x: "x", y: "y", fill: (d) => Math.hypot(d.x, d.y) })],
});
