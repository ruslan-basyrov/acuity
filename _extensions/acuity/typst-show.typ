#import "@preview/marginalia:0.3.1": wideblock, notefigure
#import "@preview/marginalia:0.3.1" as marginalia

#show: marginalia.setup.with(
  inner: (far: 25mm, width: 0pt, sep: 0pt),     // Left margin
  outer: (far: 25mm, width: 54mm, sep: 10mm),   // Right margin
  top: 25mm,
  bottom: 25mm,
  book: false,
)

// intercept footnote function with a sidenote function 
// which works properly for citations in the note
#show footnote: it => {
  marginalia.note(
    anchor-numbering: (..n) => super(numbering("1", ..n)),
    numbering: (..n) => super(numbering("1", ..n)) + h(0.25em)
  )[#{
    show place: none 
    
    // expand a citation to the full reference right in the sidenote
    show cite: c => {
      let ref-target = c.at("target", default: c.at("key", default: none))
      if c.at("form", default: "normal") != "full" {
        linebreak() + cite(ref-target, form: "full")
      } else {
        c
      }
    }

    it.body
  }]
}

// intercept citation not in full reference and move it to footnote
#show cite: it => {
  if it.form != "full" {
    footnote(cite(it.key, form: "full", supplement: it.supplement))
  } else {
    it
  }
}

// remove the note as a footnote ...
#show footnote.entry: none
// ... and also the line separating the footnote from the main page
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

