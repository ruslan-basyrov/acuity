// A map of Austria as a reference basemap. 

const staticFigure = true;
const SUBJECT_ISO = "AUT";

const NE = "https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson";

// Pad the subject's bounds by this fraction of its width and height, so the
// country reads in context and the neighbour labels have room
const PAD = [0.14, 0.21];

// Show country's name if its area surpasses the threshold.
const MIN_LABEL_AREA = 0.005;

const CITY_COUNT = 6; // as many as the frame holds without labels colliding

const RELIEF_ALPHA = 0.42;

// Set a name in caps, spaced out, for the effect like: "W O R D" on the map
const spaced = (s) => [...s.toUpperCase()].join(" ");

const spec = async ({document, width = 700}) => {
  const c = yaml.load(await loadText("_extensions/acuity/_brand.yml")).color;
  // Resolve a brand role that names a palette entry instead of giving a hex
  const col = (v) => c.palette[v] ?? v;
  const INK = {
    water:   c.palette.cyan,
    land:    col(c.light.light),
    subject: col(c.background.light),
    border:  col(c.tertiary.light),
    outline: col(c.secondary.light),
    label:   col(c.foreground.light)
  };

  const countries = await json(`${NE}/ne_50m_admin_0_countries.geojson`);
  const subject = countries.features.find((d) => d.properties.ADM0_A3 === SUBJECT_ISO);

  // Calculate the boundary box depending on the country (here, Austria)
  const [[w, s], [e, n]] = d3.geoBounds(subject);
  const [dx, dy] = [(e - w) * PAD[0], (n - s) * PAD[1]];
  const box = [[w - dx, s - dy], [e + dx, n + dy]];
  const WINDOW = d3.geoGraticule().extent(box).outline();

  // Calculate the projection: parallels at 1/6 and 5/6 of the window's latitudes
  const lat = d3.interpolate(s - dy, n + dy);
  const proj = d3.geoConicEqualArea()
    .parallels([lat(1 / 6), lat(5 / 6)])
    .rotate([-(w + e) / 2, 0]);

  // Fit the projection to the window with zero margins, so the frame is exactly
  // [0,0]-[width,height] and the relief lines up with the vector layers
  proj.fitWidth(width, WINDOW);
  const [[, top], [, bottom]] = d3.geoPath(proj).bounds(WINDOW);
  const height = Math.round(bottom - top);
  proj.fitExtent([[0, 0], [width, height]], WINDOW);

  const [lakes, rivers, places, terrain] = await Promise.all([
    json(`${NE}/ne_50m_lakes.geojson`),
    json(`${NE}/ne_50m_rivers_lake_centerlines.geojson`),
    json(`${NE}/ne_10m_populated_places_simple.geojson`),
    relief(proj, width, height)
  ]);

  // Clip the projection so that a country's area covers only its visible part,
  // and name the ones with room for a label (Plot.centroid puts it on the
  // clipped centre)
  proj.clipExtent([[0, 0], [width, height]]);
  const path = d3.geoPath(proj);
  const NEIGHBOURS = countries.features
    .filter((d) => d !== subject && path.area(d) > MIN_LABEL_AREA * width * height);

  // Take the largest towns from the place names file
  const CITIES = places.features
    .map((f) => f.properties)
    .filter((p) => p.adm0_a3 === SUBJECT_ISO)
    .sort((a, b) => b.pop_max - a.pop_max)
    .slice(0, CITY_COUNT);

  // Name goes right of its dot (side 1) for towns in the country's east half,
  // left (-1) for the west
  const side = (p) => (p.longitude < subject.properties.LABEL_X ? -1 : 1);

  return {
    projection: {type: () => proj},
    width,
    height,
    margin: 0,
    ...(document && {document}),
    marks: [
      Plot.frame({fill: INK.water, fillOpacity: 0.35}),
      Plot.geo(countries, {fill: INK.land, stroke: INK.border, strokeWidth: 0.7}),

      // Draw the terrain over the fills but under the linework, so it shades
      // the land without muddying borders, rivers or type
      terrain && Plot.image([{}], {
        src: terrain,
        width, height,
        frameAnchor: "middle",
        preserveAspectRatio: "none",
        opacity: RELIEF_ALPHA
      }),
      // Redraw the subject over the relief to keep its edge crisp
      Plot.geo(subject, {fill: "none", stroke: INK.outline, strokeWidth: 1.1}),

      // Draw whole layers: Plot clips geometry to the frame, so a river that
      // leaves the map costs a few characters
      Plot.geo(rivers, {stroke: INK.water, strokeWidth: 0.8}),
      Plot.geo(lakes, {
        fill: INK.water, fillOpacity: 0.55, stroke: INK.water, strokeWidth: 0.5
      }),

      Plot.text(NEIGHBOURS, Plot.centroid({
        text: (d) => spaced(d.properties.NAME),
        fontSize: 8.5, fill: INK.border, fontWeight: 500
      })),
      // Put the subject's name on Natural Earth's own label point
      Plot.text([subject.properties], {
        x: "LABEL_X", y: "LABEL_Y", text: (p) => spaced(p.NAME),
        fontSize: 12, fill: INK.label, fontWeight: 500
      }),

      Plot.dot(CITIES, {
        x: "longitude", y: "latitude", r: 2.2,
        fill: INK.subject, stroke: INK.label, strokeWidth: 1
      }),
      ...[1, -1].map((s) => Plot.text(CITIES.filter((p) => side(p) === s), {
        x: "longitude", y: "latitude", text: "name",
        dx: 6 * s, textAnchor: s > 0 ? "start" : "end",
        fontSize: 9.5, fill: INK.label
      })),

      Plot.frame({stroke: INK.border, strokeWidth: 0.8})
    ]
  };
};
