#import "@preview/fireside:1.0.0": fireside

#let d = yaml("build/cover_letter_data.yaml")

#show: fireside.with(
  title: [#d.sender.name],
  from-details: [
    #d.sender.name
  ],
  to-details: [
    #d.recipient.company
  ],
)

Dear Hiring Team,

#d.paragraphs.opening

#d.paragraphs.technical_fit

#d.paragraphs.company_specific

#d.paragraphs.closing

Sincerely,

#d.sender.name
