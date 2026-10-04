// A continuous opacity scale with its built-in Plot legend, which the
// prerender turns into a vector gradient.

export default ({ Plot, d3, document, width, theme }) => {
  const random = d3.randomLcg(11);
  const cells = d3.cross(d3.range(14), d3.range(7)).map(([x, y]) => ({
    x,
    y,
    v: Math.abs(Math.sin(x / 3) * Math.cos(y / 2)) * 0.7 + random() * 0.3,
  }));
  const accent = theme("accent");
  return {
    document,
    width,
    height: 240,
    x: { label: null },
    y: { label: null },
    opacity: { legend: true, color: accent, label: "invented intensity", domain: [0, 1] },
    marks: [Plot.cell(cells, { x: "x", y: "y", fill: accent, fillOpacity: "v", inset: 1 })],
  };
};
