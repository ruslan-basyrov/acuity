// The brand palette, read from _brand.yml, so the prose and the figure cannot
// disagree about a colour.

export default ({ Plot, d3, theme, width }) => {
  const palette = Object.entries(theme.palette)
    .map(([name, hex], i) => ({ name, hex, x: i % 3, y: Math.floor(i / 3) }));
  return {
    height: (width * 4) / 3,
    axis: null,
    margin: 0,
    marks: [
      Plot.cell(palette, { x: "x", y: "y", fill: "hex", inset: 1 }),
      Plot.text(palette, {
        x: "x",
        y: "y",
        text: "name",
        fill: (d) => (d3.lab(d.hex).l > 60 ? "black" : "white"),
      }),
    ],
  };
};
