// Prepended to every figures/*.fig.js by prerender.ts.
// theme(document): css variables in the browser, plain hex when prerendered.
const theme = await (async () => {
  const brand = yaml.load(await loadText("_extensions/acuity/_brand.yml"));
  const p = brand.color.palette;
  const light = { accent: brand.color.primary.light, slot1: p.blue, slot2: p.purple, slot3: p.olive };
  return (document) => {
    const paint = (role) => (document ? light[role] : `var(--fig-${role}, ${light[role]})`);
    return {
      accent: paint("accent"),
      slot: (n) => paint(`slot${n}`),
      paper: document ? p.white : `var(--bs-body-bg, ${p.white})`,
    };
  };
})();

const zeroLine = () =>
  Plot.ruleY([0], { stroke: "currentColor", strokeOpacity: 0.75, strokeWidth: 1 });

const contextLines = (rows, opts) =>
  Plot.lineY(rows, { stroke: "currentColor", strokeOpacity: 0.3, strokeWidth: 1, ...opts });

const endLabel = (rows, opts) =>
  Plot.text(rows, { textAnchor: "start", dx: 8, ...opts });
