# Acuity

A Quarto template inspired by Edward Tufte, with shared styling for HTML and Typst PDF.

## Run

Install [Quarto](https://quarto.org/docs/get-started/), then run `quarto render`
or `quarto preview`. The output goes to `_acuity/`.

`make render` and `make preview` also work; set `QUARTO=quarto` to use an
installed Quarto instead of the Makefile's `uv` runner.

## Change the design

Start with these two files in `_extensions/acuity/`:

| File | What it controls |
| --- | --- |
| `_brand.yml` | Fonts, light/dark colours, and the categorical palette order. Quarto applies the brand to both formats. |
| `_extension.yml` | Column proportions, small text, figure shape, and format-specific page settings. |

The shared settings are under `contributes.formats.common`:

```yaml
grid:
  body-width: 700px
  margin-width: 300px
  gutter-width: 20px
acuity:
  small: 0.8em
  figures:
    aspect-ratio: 2.4
    min-height: 10em
    legend-width: 12em
```

The grid uses Quarto's HTML pixel widths. PDF scales the columns and gutter
together to fit between the paper margins. `small` is relative to body text
and controls captions, notes, figure labels, and legends. The aspect ratio
is width divided by height, excluding the legend. `min-height` keeps narrow
margin plots readable.

Keep body font sizes under each format's `fontsize`; keep font families and
colours in the brand. Paper size and outside margins belong to `typst`.
Supported papers are A4, A5, US Letter, and US Legal. HTML uses Quarto's
responsive article layout; figures shrink with their columns on small screens.

For project-specific changes, override `grid` or `acuity` in `_quarto.yml`
or a document's YAML header. Changes shared by both formats belong at the
top level, rather than inside a single format.

## Add a figure

Create `figures/example.fig.js` with a default function returning
[Observable Plot options](https://observablehq.github.io/plot/features/plots):

```js
export default ({ Plot }) => ({
  marks: [Plot.dot([1, 4, 2, 5])],
});
```

Then reference it as an ordinary image:

```markdown
![A short caption.](figures/example.fig.js){#fig-example}
```

Use `.column-margin` for the margin, `.column-page-right` for both columns,
or `width="60%"` for part of the column. Each figure receives
`{ Plot, d3, theme, width, em, read }`: `width` and `em` are drawing units,
`theme` contains brand colours and the body font, and `read(path)` reads text
relative to the project. Figures inherit the shared shape; override `height`
only when the content requires it. Colour, symbol, and opacity legends use
the same SVG in both formats.

## Read the implementation

`acuity.lua` coordinates three steps: collect images, render a batch, replace
images. `layout.lua` handles dimensions and `theme.lua` reads brand settings
using Pandoc and Quarto. `figures.js` renders Plot options; `legends.js` adds
SVG legends. The small CSS and Typst files style notes and captions.

The renderer pins its existing Plot, D3, and JSDOM dependencies. Quarto's
bundled Deno runs them; no separate Node installation or bundler is needed.
The first render needs internet access for those packages and Google Fonts.
There is no separate YAML library or client-side chart runtime.

Run `make check` to render both formats and check figure configuration and SVG output.
