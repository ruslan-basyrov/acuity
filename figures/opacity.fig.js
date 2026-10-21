// How far each point lies from the vertical axis, as opacity. Its legend is
// a ramp from transparent to the colour of the text.

import points from "./points.js";

export default ({ Plot, d3 }) => ({
  opacity: { legend: true, label: "|x|" },
  marks: [
    Plot.dot(points(d3), { x: "x", y: "y", fill: "currentColor", fillOpacity: (d) => Math.abs(d.x) }),
  ],
});
