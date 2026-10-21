// Three invented series. They take the brand's categorical colours, and their
// legend is drawn above them.

export default ({ Plot, d3, em }) => {
  const random = d3.randomNormal.source(d3.randomLcg(7))(0, 1);
  const series = ["Vienna", "Graz", "Linz"].flatMap((city) => {
    let change = 0;
    return d3.range(52).map((week) => ({ city, week, change: (change += random()) }));
  });
  return {
    marginBottom: 3 * em,
    color: { legend: true },
    x: { label: "Week", labelAnchor: "center" },
    y: { label: "Change", grid: true },
    marks: [
      Plot.ruleY([0]),
      Plot.lineY(series, { x: "week", y: "change", stroke: "city" }),
    ],
  };
};
