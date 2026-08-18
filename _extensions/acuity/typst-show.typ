#import "@preview/marginalia:0.3.1": note, notefigure, wideblock
#import "@preview/marginalia:0.3.1" as marginalia

// Quarto colours note callouts with the brand's primary, so send them to `info` to match HTML.
#let quarto-callout = callout
#let callout(background_color: none, icon_color: none, ..args) = quarto-callout(
  background_color: if icon_color == brand-color.primary { brand-color-background.info } else { background_color },
  icon_color: if icon_color == brand-color.primary { brand-color.info } else { icon_color },
  ..args,
)

#show: marginalia.setup.with(
  inner: (far: 25mm, width: 0pt, sep: 0pt),     // Left margin
  outer: (far: 25mm, width: 54mm, sep: 10mm),   // Right margin
  top: 25mm,
  bottom: 25mm,
  book: false,
  // Tighter than the 12pt default so pages with many notes still fit.
  clearance: 6pt,
)

// One style for every margin note so references and remarks look the same.
#let sidenote = marginalia.note.with(
  text-style: (size: 8pt, style: "normal", weight: "regular"),
  par-style: (spacing: 0.9em, leading: 0.45em, hanging-indent: 0pt),
)

// Quarto anchors a margin figure at the first baseline of its caption, which
// puts the anchor a whole figure height above the line the figure sits on.
// Marginalia orders the margin by those anchors, so a figure can overtake a note
// that comes before it in the text. Anchoring the top of the figure keeps the
// margin in the order of the source.
#let quarto-notefigure = notefigure
#let notefigure(..args) = quarto-notefigure(..args.pos(), ..args.named() + (alignment: "top"))

// Unfinished text, marked by `::: draft` and `[...]{.draft}`. The wash shows
// how far the run goes; the label is what says the text is not done. It bleeds
// into the left margin, away from the notes on the right.
#let draftblock(body) = block(
  width: 100%,
  fill: brand-color-background.sand,
  outset: (left: 8mm, right: 3mm, y: 3mm),
  above: 1.4em,
  below: 1.4em,
  {
    block(
      below: 0.6em,
      text(size: 7pt, tracking: 0.08em, fill: brand-color.primary, upper("draft")),
    )
    body
  },
)

#let draftspan(body) = highlight(fill: brand-color-background.sand, extent: 1pt, body)

// Tables. tables.lua drops the column widths pandoc reads out of the
// markdown source, so columns size to their content. Rules sit at 60% ink,
// below the text, the way a plot's frame sits below its marks.
#let tablerule = 0.7pt + brand-color.foreground.transparentize(40%)
#show table: set par(justify: false)
#show table: set text(hyphenate: false, size: 9pt, number-width: "tabular")
#show table: set align(left)
#set table(inset: (x: 0.6em, y: 0.5em), stroke: none)
#set table.hline(stroke: tablerule)
#show table.cell.where(y: 0): set text(weight: "bold")
#show table: it => block(stroke: (top: tablerule, bottom: tablerule), inset: (y: 0.4em), it)

// Captions take the secondary colour. A caption moved to the margin is
// excepted and keeps the sidenotes' ink (captions.lua).
#show figure.caption: set text(size: 8.5pt, fill: brand-color.secondary)

// Turn every footnote into a margin note.
#show footnote: it => {
  sidenote(
    anchor-numbering: (..n) => super(numbering("1", ..n)),
    numbering: (..n) => super(numbering("1", ..n)) + h(0.25em),
  )[#{
    show place: none
    it.body
  }]
}

// citations.lua renders each citation as a raised bracketed number and calls `sidenote` for the reference.

// With `sidenote-citations: false` the citations and the bibliography come from
// citeproc, which makes both of them links: a citation to its entry, and the
// entry back to the first mention of it. The brand colours a link, but these two
// are read as text, so they keep the colour of the text around them.
#show link: it => {
  let dest = if type(it.dest) == label { str(it.dest) } else { "" }
  if dest.starts-with("ref-") or dest.starts-with("cite-") {
    text(fill: brand-color.foreground, it)
  } else { it }
}

// The bibliography carries no margin notes, so give it the full page width. Its
// heading stays outside the wide block, since the level-1 rule breaks the page
// and a page break cannot happen inside one.
#let typst-bibliography = bibliography
#let bibliography(..args) = {
  heading(level: 1)[References]
  wideblock(typst-bibliography(..args, title: none$if(acuity-csl)$, style: "$acuity-csl$"$endif$))
}

// Drop the copy of the note at the bottom of the page.
#show footnote.entry: none
// Drop the line that separated that copy from the body.
#set footnote.entry(separator: none)



#show: doc => book(
$if(title)$
  title: [$title$],
$endif$
$if(subtitle)$
  subtitle: [$subtitle$],
$endif$
$if(by-author)$
  authors: (
$for(by-author)$
$if(it.name.literal)$
    ( name: [$it.name.literal$],
      affiliation: [$for(it.affiliations)$$it.name$$sep$, $endfor$],
      email: [$it.email$] ),
$endif$
$endfor$
    ),
$endif$
$if(date)$
  date: [$date$],
$endif$
$if(lang)$
  lang: "$lang$",
$endif$
$if(region)$
  region: "$region$",
$endif$
$if(abstract)$
  abstract: [$abstract$],
  abstract-title: "$labels.abstract$",
$endif$
$if(papersize)$
  paper: "$papersize$",
$endif$
$if(mainfont)$
  font: $mainfont$,
$elseif(brand.typography.base.family)$
  font: $brand.typography.base.family$,
$endif$
$if(fontsize)$
  fontsize: $fontsize$,
$elseif(brand.typography.base.size)$
  fontsize: $brand.typography.base.size$,
$endif$
$if(title)$
$if(brand.typography.headings.family)$
  heading-family: $brand.typography.headings.family$,
$endif$
$if(brand.typography.headings.weight)$
  heading-weight: $brand.typography.headings.weight$,
$endif$
$if(brand.typography.headings.style)$
  heading-style: "$brand.typography.headings.style$",
$endif$
$if(brand.typography.headings.decoration)$
  heading-decoration: "$brand.typography.headings.decoration$",
$endif$
$if(brand.typography.headings.color)$
  heading-color: $brand.typography.headings.color$,
$endif$
$if(brand.typography.headings.line-height)$
  heading-line-height: $brand.typography.headings.line-height$,
$endif$
$endif$
$if(section-numbering)$
  sectionnumbering: "$section-numbering$",
$endif$
$if(toc)$
  toc: $toc$,
$endif$
$if(toc-title)$
  toc_title: [$toc-title$],
$endif$
$if(toc-indent)$
  toc_indent: $toc-indent$,
$endif$
  toc_depth: $toc-depth$,
  doc,
)

