// How far each point lies from the centre, in bands. Its legend is a ramp of
// blocks.

import points from "./points.js";

export default ({ Plot, d3 }) => ({
  color: {
    legend: true,
    type: "threshold",
    domain: [0.5, 1, 1.5, 2],
    scheme: "YlGnBu",
    label: "Distance from centre",
  },
  marks: [Plot.dot(points(d3), { x: "x", y: "y", fill: (d) => Math.hypot(d.x, d.y) })],
});
