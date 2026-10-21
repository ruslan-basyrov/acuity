// Acuity's Typst rules. layout.lua sets `acuity-small`, the small size, just
// before this file.

// Notes and captions share the small size, as they do in HTML;
// marginalia would set notes at 9.35pt whatever the body size. Quarto writes
// notes, margin figures and margin captions as calls to these names, so
// rebinding them reaches them all. Its footnote rule, set after this file,
// calls `column-sidenote`.
#let note = marginalia.note.with(text-style: (size: acuity-small))

// Quarto anchors a margin figure by the first line of its caption, which hangs
// the figure above the text it belongs to; HTML sets its top level with it.
#let notefigure(..args) = {
  let named = (text-style: (size: acuity-small)) + args.named()
  if named.at("alignment", default: "baseline") == "baseline" { named.alignment = "top" }
  marginalia.notefigure(..args.pos(), ..named)
}

#let column-sidenote(body) = context {
  let number = counter(footnote).display("1")
  super(number)
  note(alignment: "baseline", shift: auto, counter: none)[#super(number) #body]
}

#show figure.caption: set text(size: acuity-small)
#show figure.caption: set align(start)
