#let d = yaml("build/cover_letter_data.yaml")

#set page(paper: "a4", margin: (x: 2.8cm, y: 3cm))
#set text(font: ("Fira Sans", "Liberation Sans", "Arial"), size: 11pt, lang: "en")
#set par(leading: 0.7em, spacing: 1.4em)

Dear Hiring Team,

#d.paragraphs.opening

#d.paragraphs.technical_fit

#d.paragraphs.company_specific

#d.paragraphs.closing

Warm regards,

#d.sender.name
