// A map of Austria as a reference basemap.

const NE = "https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@v5.1.2/geojson";

// Pad Austria's bounds by this fraction of its width and height, so the
// country reads in context and the neighbour labels have room
const PAD = [0.14, 0.21];

// Show country's name if its area surpasses the threshold.
const MIN_LABEL_AREA = 0.005;

// The six largest towns, as Natural Earth's populated places rank them
const CITIES = [
  {name: "Vienna", lon: 16.36, lat: 48.2},
  {name: "Linz", lon: 14.29, lat: 48.32},
  {name: "Graz", lon: 15.41, lat: 47.08},
  {name: "Salzburg", lon: 13.04, lat: 47.81},
  {name: "Innsbruck", lon: 11.41, lat: 47.28},
  {name: "Klagenfurt", lon: 14.31, lat: 46.62}
];

const RELIEF_ALPHA = 0.42;

// Set a name in caps, spaced out, for the effect like: "W O R D" on the map
const spaced = (s) => [...s.toUpperCase()].join(" ");

export default async ({Plot, d3, document, width, brand, json, relief}) => {
  const {palette, secondary, tertiary, foreground} = brand.color;
  const INK = {
    water:   palette.cyan,
    land:    palette.white,
    border:  tertiary.light,
    outline: secondary.light,
    label:   foreground.light
  };

  const countries = await json(`${NE}/ne_50m_admin_0_countries.geojson`);
  const austria = countries.features.find((d) => d.properties.ADM0_A3 === "AUT");

  // Fit Austria Lambert, the country's official projection (EPSG:31287), to the
  // padded box. The relief is warped into the same projection
  const [[w, s], [e, n]] = d3.geoBounds(austria);
  const [dx, dy] = [(e - w) * PAD[0], (n - s) * PAD[1]];
  const box = d3.geoGraticule().extent([[w - dx, s - dy], [e + dx, n + dy]]).outline();
  const proj = d3.geoConicConformal().parallels([46, 49]).rotate([-13 - 1 / 3, 0])
    .fitWidth(width, box);
  const height = Math.round(d3.geoPath(proj).bounds(box)[1][1]);

  // Clip the projection so that a country's area covers only its visible part,
  // and name the ones with room for a label (Plot.centroid puts it on the
  // clipped centre)
  proj.clipExtent([[0, 0], [width, height]]);
  const path = d3.geoPath(proj);
  const NEIGHBOURS = countries.features
    .filter((d) => d !== austria && path.area(d) > MIN_LABEL_AREA * width * height);

  const [lakes, rivers, terrain] = await Promise.all([
    json(`${NE}/ne_50m_lakes.geojson`),
    json(`${NE}/ne_50m_rivers_lake_centerlines.geojson`),
    relief(proj, width, height)
  ]);

  return {
    projection: proj,
    width,
    height,
    margin: 0,
    document,
    marks: [
      Plot.geo(countries, {fill: INK.land, stroke: INK.border, strokeWidth: 0.7}),

      // Draw the terrain over the fills but under the linework, so it shades
      // the land without muddying borders, rivers or type
      Plot.image([{}], {
        src: terrain,
        width, height,
        frameAnchor: "middle",
        preserveAspectRatio: "none",
        opacity: RELIEF_ALPHA
      }),
      // Redraw Austria over the relief to keep its edge crisp
      Plot.geo(austria, {fill: "none", stroke: INK.outline, strokeWidth: 1.1}),

      // Draw whole layers: the projection clips geometry to the frame, so a
      // river that leaves the map costs a few characters
      Plot.geo(rivers, {stroke: INK.water, strokeWidth: 0.8}),
      Plot.geo(lakes, {
        fill: INK.water, fillOpacity: 0.55, stroke: INK.water, strokeWidth: 0.5
      }),

      Plot.text(NEIGHBOURS, Plot.centroid({
        text: (d) => spaced(d.properties.NAME),
        fontSize: 8.5, fill: INK.border, fontWeight: 500
      })),
      // Put Austria's name on Natural Earth's own label point
      Plot.text([austria.properties], {
        x: "LABEL_X", y: "LABEL_Y", text: (p) => spaced(p.NAME),
        fontSize: 12, fill: INK.label, fontWeight: 500
      }),

      Plot.dot(CITIES, {
        x: "lon", y: "lat", r: 2.2,
        fill: INK.land, stroke: INK.label, strokeWidth: 1
      }),
      Plot.text(CITIES, {
        x: "lon", y: "lat", text: "name", dx: 6, textAnchor: "start",
        fontSize: 9.5, fill: INK.label
      }),

      Plot.frame({stroke: INK.border, strokeWidth: 0.8})
    ]
  };
};
