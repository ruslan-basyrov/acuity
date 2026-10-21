// How light each palette colour is, which decides whether text on it is set
// in black or white (the line at L* = 60).

export default ({ Plot, d3, theme, em }) => {
  const palette = Object.entries(theme.palette)
    .map(([name, hex]) => ({ name, hex, lightness: d3.lab(hex).l }));
  return {
    height: 16 * em,
    marginLeft: 4 * em,
    marginBottom: 3 * em,
    x: { domain: [0, 100], label: "Lightness (L*)", labelAnchor: "center" },
    y: { label: null },
    marks: [
      Plot.barX(palette, { x: "lightness", y: "name", fill: "hex", sort: { y: "x" } }),
      Plot.ruleX([60], { strokeDasharray: "3,3" }),
      Plot.ruleX([0]),
    ],
  };
};
