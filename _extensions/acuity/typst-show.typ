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

