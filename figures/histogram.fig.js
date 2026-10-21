// An invented normal sample, binned. It has no legend.

export default ({ Plot, d3 }) => {
  const random = d3.randomNormal.source(d3.randomLcg(3))();
  return {
    marks: [
      Plot.rectY({ length: 10000 }, Plot.binX({ y: "count" }, { x: random })),
      Plot.ruleY([0]),
    ],
  };
};
