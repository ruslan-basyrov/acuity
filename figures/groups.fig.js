// Three invented groups, binned and stacked. They take the brand's categorical
// colours, and their legend is drawn above them.

export default ({ Plot, d3 }) => {
  const groups = ["A", "B", "C"].flatMap((group, i) => {
    const random = d3.randomNormal.source(d3.randomLcg(i + 1))(i * 1.5, 1);
    return Array.from({ length: 3000 }, () => ({ group, x: random() }));
  });
  return {
    color: { legend: true },
    marks: [
      Plot.rectY(groups, Plot.binX({ y: "count" }, { x: "x", fill: "group" })),
      Plot.ruleY([0]),
    ],
  };
};
