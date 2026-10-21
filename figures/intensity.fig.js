// An invented intensity over a grid, as shades of the accent colour. Its
// legend is a ramp, drawn above it.

export default ({ Plot, d3, theme, width }) => {
  const random = d3.randomLcg(11);
  const cells = d3.cross(d3.range(36), d3.range(6)).map(([x, y]) => ({
    x,
    y,
    v: Math.abs(Math.sin(x / 5) * Math.cos(y / 2)) * 0.7 + random() * 0.3,
  }));
  return {
    height: width / 6,
    axis: null,
    margin: 0,
    opacity: { domain: [0, 1], legend: true, color: theme.accent, label: "Invented intensity" },
    marks: [Plot.cell(cells, { x: "x", y: "y", fill: theme.accent, fillOpacity: "v", inset: 0.5 })],
  };
};
