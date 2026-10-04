// The brand palette swatches, read from _brand.yml so the prose and the figure
// cannot disagree about a colour.

export default ({Plot, d3, document, brand}) => {
  const palette = Object.entries(brand.color.palette)
    .map(([name, hex], i) => ({name, hex, x: i % 4, y: -Math.floor(i / 4)}));
  return {
    axis: null,
    margin: 5,
    aspectRatio: 1,
    document,
    marks: [
      Plot.cell(palette, {x: "x", y: "y", fill: "hex", stroke: "white", strokeWidth: 2}),
      Plot.text(palette, {
        x: "x",
        y: "y",
        text: (d) => `${d.name}\n${d.hex}`,
        fill: (d) => (d3.lab(d.hex).l > 60 ? "black" : "white"),
        fontWeight: "bold"
      })
    ]
  };
};
