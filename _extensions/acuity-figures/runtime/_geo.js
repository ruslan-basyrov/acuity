// Cartography helpers, passed to every figure by prerender.ts.
// Build-time only, so this never ships to the browser.

import * as d3 from "npm:d3";
import { PNG } from "npm:pngjs";

// Downloads, kept under build/.cache and shared by every run. A cached URL is
// never fetched again, so pin versioned ones; `make clean` drops the lot
const CACHE = `${Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd()}/build/.cache`;

const cached = async (url) => {
  const file = `${CACHE}/${encodeURIComponent(url)}`;
  return Deno.readFile(file).catch(async () => {
    const r = await fetch(url);
    if (!r.ok) throw Object.assign(new Error(`${r.status} ${url}`), { status: r.status });
    const bytes = new Uint8Array(await r.arrayBuffer());
    await Deno.mkdir(CACHE, { recursive: true });
    await Deno.writeFile(file, bytes);
    return bytes;
  });
};

export const json = async (url) => JSON.parse(new TextDecoder().decode(await cached(url)));

const TILE = 256;

// The pixel grid of web map tiles at a zoom, as a d3 projection (Web Mercator
// is d3's Mercator)
const tileGrid = (zoom) => {
  const size = TILE * 2 ** zoom;
  return d3.geoMercator().scale(size / (2 * Math.PI)).translate([size / 2, size / 2]);
};

// Draw web map tiles in a projection's frame, as a PNG data URI for Plot.image.
// `tiles` is a PNG tile URL with {z}, {x} and {y}. Each output pixel takes the
// tile pixel under its centre, so any d3 projection works. Plot's raster mark
// would need a canvas 2D context, which JSDOM does not provide. `paint` may
// recolour each output pixel's RGBA in place
export const warp = async (proj, width, height, tiles, paint = () => {}) => {
  // Take the coarsest zoom whose pixels are no larger than the frame's, as
  // measured across its centre, and draw at that zoom's resolution
  const [a, b] = [0, 1].map((dx) => tileGrid(0)(proj.invert([width / 2 + dx, height / 2])));
  const step = Math.hypot(b[0] - a[0], b[1] - a[1]);
  const zoom = Math.ceil(-Math.log2(step));
  const w = Math.round(width * step * 2 ** zoom);
  const h = Math.round(height * step * 2 ** zoom);

  // Find where each output pixel's centre falls on the tile grid
  const grid = tileGrid(zoom);
  const x = new Float64Array(w * h).fill(NaN);
  const y = new Float64Array(w * h).fill(NaN);
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const lonlat = proj.invert([((i + 0.5) * width) / w, ((j + 0.5) * height) / h]);
      if (lonlat) [x[j * w + i], y[j * w + i]] = grid(lonlat);
    }
  }

  // Copy every tile under the frame into one mosaic. A regional source has no
  // tiles outside its region, so a missing one stays transparent
  const [tx0, tx1] = d3.extent(x, (v) => Math.floor(v / TILE));
  const [ty0, ty1] = d3.extent(y, (v) => Math.floor(v / TILE));
  const mosaic = new PNG({ width: (tx1 - tx0 + 1) * TILE, height: (ty1 - ty0 + 1) * TILE });
  await Promise.all(
    d3.cross(d3.range(tx0, tx1 + 1), d3.range(ty0, ty1 + 1)).map(async ([tx, ty]) => {
      const url = tiles.replace("{z}", zoom).replace("{x}", tx).replace("{y}", ty);
      const bytes = await cached(url).catch((e) => { if (e.status !== 404) throw e; });
      if (!bytes) return;
      PNG.bitblt(PNG.sync.read(Buffer.from(bytes)), mosaic, 0, 0, TILE, TILE, (tx - tx0) * TILE, (ty - ty0) * TILE);
    }),
  );

  // Pixels outside the projection's domain stay transparent
  const png = new PNG({ width: w, height: h });
  for (let k = 0; k < w * h; k++) {
    const s = 4 * ((Math.floor(y[k]) - ty0 * TILE) * mosaic.width + Math.floor(x[k]) - tx0 * TILE);
    if (Number.isNaN(s)) continue;
    png.data.set(mosaic.data.subarray(s, s + 4), 4 * k);
    paint(png.data.subarray(4 * k, 4 * k + 4));
  }

  // Store only the channels the pixels use: a relief is grey and opaque, so it
  // needs one channel of four
  const grey = png.data.every((v, k) => k % 4 === 3 || v === png.data[k - (k % 4)]);
  const opaque = png.data.every((v, k) => k % 4 !== 3 || v === 255);
  const colorType = (grey ? 0 : 2) + (opaque ? 0 : 4);
  return `data:image/png;base64,${PNG.sync.write(png, { colorType }).toString("base64")}`;
};

// Read surface normals from AWS Open Data "Terrain Tiles" (public, no key),
// stored as RGB = 128 * (n + 1), x east and y north, with the slope halved.
// Their sources and the credit each asks for:
// https://github.com/tilezen/joerd/blob/master/docs/attribution.md
const NORMALS = "https://s3.amazonaws.com/elevation-tiles-prod/normal/{z}/{x}/{y}.png";
const AZIMUTH = 315;
const ALTITUDE = 45;
const EXAGGERATION = 1.6;

// Paint the shaded relief under a projection's frame, lit as normal-dot-light
export const relief = (proj, width, height) => {
  const az = (AZIMUTH * Math.PI) / 180;
  const alt = (ALTITUDE * Math.PI) / 180;
  const lx = Math.sin(az) * Math.cos(alt);
  const ly = Math.cos(az) * Math.cos(alt);
  const lz = Math.sin(alt);
  const ex = 2 * EXAGGERATION; // doubled, to undo the tiles' halving

  return warp(proj, width, height, NORMALS, (pixel) => {
    const [nx, ny, nz] = [ex * (pixel[0] / 128 - 1), ex * (pixel[1] / 128 - 1), pixel[2] / 128 - 1];
    const s = Math.max(0, (nx * lx + ny * ly + nz * lz) / Math.hypot(nx, ny, nz));
    pixel.fill(Math.round(s * 255), 0, 3);
    pixel[3] = 255;
  });
};
