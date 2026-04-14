#import "@preview/lavandula:0.1.1": *

// ── Data ──────────────────────────────────────────────────────────────────────
#let d = yaml("build/tailored.yaml")

// ── Layout knobs ──────────────────────────────────────────────────────────────
#let body-size    = 9pt
#let body-leading = 0.60em
#let sidebar-w    = 35%

// ── Theme ─────────────────────────────────────────────────────────────────────
#show: lavandula-theme

#set text(size: body-size, lang: "en")
#set par(leading: body-leading)
#set block(spacing: 0.9em)
#set document(
  title:  d.personal.name + " — Resume",
  author: d.personal.name,
  date:   none,
)

// ── Helpers ───────────────────────────────────────────────────────────────────
#let bullet-list(items) = icon-list(
  items.map(b => (icon: "circle-check", text: b))
)

// Experience entry with an optional company logo inline with the title.
// The logo sits on the same line as the company/role heading; body runs full-width below.
#let logo-section-element(title: "", info: "", logo: none, body) = {
  let logo-h = 2.1em   // scales with font size; tweak if needed
  let title-content = {
    if logo != none {
      box(height: logo-h, baseline: 25%, image(logo, height: 100%))
      h(5pt)
    }
    text(weight: "semibold", title)
  }
  block(
    breakable: false,
    inset: (top: 3pt),
    width: 100%,
    below: 1.7em,
    {
      grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        title-content,
        text(size: 7pt, info),
      )
      v(4pt)
      set par(justify: true, spacing: 1em)
      body
    },
  )
}

#let fmt-roles(roles) = {
  if roles.len() == 1 {
    roles.at(0).start + " – " + roles.at(0).end
  } else {
    roles.last().start + " – " + roles.first().end
  }
}

#let level-ratio(s) = int(s.replace("%", "")) * 1%

// ── Main document ─────────────────────────────────────────────────────────────
#cv(
  sidebar-position: "left",
  sidebar-width:    sidebar-w,
  sidebar: [
    = #d.personal.name
    ==== #d.personal.tagline

    #contact-list((
      (icon: "at",           icon-solid: true, text: link("mailto:" + d.personal.email)[#d.personal.email]),
      (icon: "linkedin",                       text: link(d.personal.linkedin_url)[#d.personal.linkedin_label]),
      (icon: "github",                         text: link(d.personal.github_url)[#d.personal.github_label]),
      (icon: "location-dot", icon-solid: true, text: d.personal.location),
      (icon: "phone",        icon-solid: true, text: d.personal.phone),
    ))

    #sidebar-section(title: "About")[
      #d.summary
    ]

    #for group in d.skills {
      skill-group(
        name:   group.group,
        icon:   group.icon,
        skills: group.items,
      )
    }
  ],
  main-content: [

    #section(title: "Experience")[
      #for job in d.experience {
        let multi = job.roles.len() > 1
        let title-text = if multi {
          job.company
        } else {
          job.company + " — " + job.roles.at(0).title
        }
        let info-text = fmt-roles(job.roles) + " · " + job.location
        let logo-path = if "logo" in job { job.logo } else { none }

        logo-section-element(
          title: title-text,
          info:  [_#info-text _],
          logo:  logo-path,
          {
            if multi {
              for r in job.roles {
                text(weight: "semibold")[#r.title]
                text(style: "italic")[ · #r.start – #r.end]
                linebreak()
              }
              v(0.25em)
            }
            if job.company_description != "" {
              text(style: "italic", size: 8pt)[#job.company_description]
              v(0.2em)
            }
            bullet-list(job.bullets)
            context {
              let pos = here()
              let p = pos.position()
              [#metadata((page: pos.page(), y: p.y.pt())) <exp-entry-end>]
            }
          },
        )
      }
    ]

    #section(title: "Education")[
      #for edu in d.education {
        let grade-text = if edu.grade != "" { " — " + edu.grade } else { "" }
        section-element-advanced(
          title:          edu.institution,
          info-top-left:  edu.year,
          info-top-right: edu.location,
          icon:           fa-icon("building-columns"),
          [_#edu.degree#grade-text _],
        )
      }
    ]

    #section(title: "Awards & Publications")[
      #icon-list(
        d.awards_and_publications.map(a => (
          icon: a.icon,
          text: a.text,
        ))
      )
    ]

  ],
)

// ── Page height capture for gap measurement ───────────────────────────────
#context {
  [#metadata(page.height.pt()) <page-height-pt>]
}

// ── Hard 2-page guard ─────────────────────────────────────────────────────
#context {
  if sys.inputs.at("skip-assert", default: "false") != "true" {
    let total = counter(page).final().at(0)
    assert(
      total <= 2,
      message: "Resume is " + str(total) + " pages — must be ≤ 2. Run `make resume` to auto-trim.",
    )
  }
}
