// Cartography helpers, passed by the runner into figures that use them.
// Build-time only, so this never ships to the browser.

import * as d3 from "npm:d3";
import { PNG } from "npm:pngjs";

export const json = async (url) => (await fetch(url)).json();

// Read elevation from AWS Open Data "Terrain Tiles" (terrarium, public, no key):
//   elevation_m = R * 256 + G + B / 256 - 32768
const DEM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium";
const ZOOM = 8;
const SS = 2; // supersampling, output pixels per figure pixel
const AZIMUTH = 315;
const ALTITUDE = 45;
const EXAGGERATION = 1.6;

const TILE = 256;

// Decoded elevation tiles, shared by every figure in the run and, through
// build/.dem, by every run. A tile is immutable at its z/x/y, so it never goes
// stale; `make clean` drops the lot.
const CACHE = `${Deno.env.get("QUARTO_PROJECT_DIR") ?? Deno.cwd()}/build/.dem`;
await Deno.mkdir(CACHE, { recursive: true });
const tiles = new Map();

const tile = (tx, ty) => {
  const key = `${ZOOM}/${tx}/${ty}`;
  if (!tiles.has(key)) {
    tiles.set(key, (async () => {
      const file = `${CACHE}/${ZOOM}-${tx}-${ty}.bin`;
      const hit = await Deno.readFile(file).catch(() => null);
      if (hit) return new Float32Array(hit.buffer, hit.byteOffset, hit.byteLength / 4);

      const r = await fetch(`${DEM}/${key}.png`);
      if (!r.ok) return null;
      const t = PNG.sync.read(Buffer.from(await r.arrayBuffer()));
      const a = new Float32Array(TILE * TILE);
      for (let y = 0; y < TILE; y++) {
        for (let x = 0; x < TILE; x++) {
          const i = (y * t.width + x) * 4;
          a[y * TILE + x] =
            Math.max(0, t.data[i] * TILE + t.data[i + 1] + t.data[i + 2] / TILE - 32768);
        }
      }
      await Deno.writeFile(file, new Uint8Array(a.buffer));
      return a;
    })());
  }
  // the promise, so figures running concurrently share one fetch
  return tiles.get(key);
};

const lon2px = (lon) => ((lon + 180) / 360) * TILE * 2 ** ZOOM;
const lat2px = (lat) =>
  ((1 - Math.asinh(Math.tan((lat * Math.PI) / 180)) / Math.PI) / 2) * TILE * 2 ** ZOOM;

// Calculate the lon/lat extent the frame covers by sampling its whole border:
// under a conic projection the corners reach past the fitted window
const frameExtent = (proj, w, h, n = 128) => d3.geoBounds({
  type: "MultiPoint",
  coordinates: d3.range(n + 1)
    .flatMap((i) => { const t = i / n; return [[t * w, 0], [t * w, h], [0, t * h], [w, t * h]]; })
    .map((p) => proj.invert(p))
    .filter((ll) => ll?.every(Number.isFinite)),
}).flat();

// Paint the shaded relief as a PNG data URI for Plot.image. Plot's raster mark
// would need a canvas 2D context, which JSDOM does not provide
export const relief = async (proj, width, height) => {
  const ext = frameExtent(proj, width, height);
  const [tx0, tx1] = [ext[0], ext[2]].map((lon) => Math.floor(lon2px(lon) / TILE));
  const [ty0, ty1] = [ext[3], ext[1]].map((lat) => Math.floor(lat2px(lat) / TILE));
  const cols = tx1 - tx0 + 1;
  const rows = ty1 - ty0 + 1;

  // Copy the tiles into one flat mosaic, so sampling is an index rather than a
  // string key per pixel. Untouched cells stay 0, so a missing tile reads as sea
  const dem = new Float32Array(cols * TILE * rows * TILE);
  const got = await Promise.all(
    d3.cross(d3.range(tx0, tx1 + 1), d3.range(ty0, ty1 + 1)).map(async ([tx, ty]) => {
      const a = await tile(tx, ty);
      if (!a) return false;
      for (let y = 0; y < TILE; y++) {
        dem.set(
          a.subarray(y * TILE, (y + 1) * TILE),
          ((ty - ty0) * TILE + y) * cols * TILE + (tx - tx0) * TILE,
        );
      }
      return true;
    }),
  );
  if (!got.some(Boolean)) return null;

  const w = Math.round(width * SS);
  const h = Math.round(height * SS);
  const z = new Float32Array(w * h);
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const ll = proj.invert([(i + 0.5) / SS, (j + 0.5) / SS]);
      if (!ll?.every(Number.isFinite)) continue;
      const gx = Math.floor(lon2px(ll[0])) - tx0 * TILE;
      const gy = Math.floor(lat2px(ll[1])) - ty0 * TILE;
      if (gx >= 0 && gy >= 0 && gx < cols * TILE && gy < rows * TILE) {
        z[j * w + i] = dem[gy * cols * TILE + gx];
      }
    }
  }

  // Calculate the ground distance per output pixel, so slope comes out in real
  // units. An equal-area conic holds scale near its standard parallels
  const mPerPx = 6371008.8 / (proj.scale() * SS);

  // Light the surface as normal-dot-light; the slope/aspect formulation is easy
  // to sign-flip, because rows run north to south
  const az = (AZIMUTH * Math.PI) / 180;
  const alt = (ALTITUDE * Math.PI) / 180;
  const lx = Math.sin(az) * Math.cos(alt);
  const ly = Math.cos(az) * Math.cos(alt);
  const lz = Math.sin(alt);

  // Write greyscale with no alpha: the shading is one luminance ramp and its
  // transparency is constant, so both belong on the <image>
  const png = new PNG({ width: w, height: h });
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const iw = Math.max(0, i - 1), ie = Math.min(w - 1, i + 1);
      const jn = Math.max(0, j - 1), js = Math.min(h - 1, j + 1);
      const nx = (-EXAGGERATION * (z[j * w + ie] - z[j * w + iw])) / ((ie - iw) * mPerPx);
      const ny = (-EXAGGERATION * (z[jn * w + i] - z[js * w + i])) / ((js - jn) * mPerPx);
      const s = Math.max(0, Math.min(1, (nx * lx + ny * ly + lz) / Math.hypot(nx, ny, 1)));
      const k = (j * w + i) * 4;
      png.data.fill(Math.round(s * 255), k, k + 3);
      png.data[k + 3] = 255;
    }
  }

  return `data:image/png;base64,${PNG.sync.write(png, { colorType: 0 }).toString("base64")}`;
};
