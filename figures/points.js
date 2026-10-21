// Six hundred invented points in three groups, shared by the figures that
// show how a colour, symbol or opacity scale is read.

export default (d3) => {
  const random = d3.randomNormal.source(d3.randomLcg(5))();
  return Array.from({ length: 600 }, (_, i) => ({ x: random(), y: random(), group: "ABC"[i % 3] }));
};
