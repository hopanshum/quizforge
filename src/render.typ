// Rendering: exam and answer-key modes, cover page, answer grid, and the
// make-exam() entry point shared by both authoring front-ends.

#import "base.typ": LETTERS, key-color, mode-state, q-state, blank-counter, cur-q-state, plaintext
#import "realize.typ": realize, meta-of

#let marks-tag(m) = text(
  size: 9pt,
  style: "italic",
  fill: gray.darken(40%),
  "[" + str(m) + " " + (if m == 1 { "mark" } else { "marks" }) + "]",
)

#let key-note(title, body, fill-c, stroke-c) = block(
  width: 100%,
  fill: fill-c,
  stroke: (left: 2pt + stroke-c),
  inset: (x: 8pt, y: 6pt),
  radius: 2pt,
  text(size: 9.5pt, strong(title + ". ") + body),
)

#let _render-options(entry, key) = {
  let deco-of = o => {
    let mark = key and o.correct
    t => if mark { text(fill: key-color, weight: "bold", t) } else { t }
  }
  if entry.q.at("compact", default: false) {
    // space-saving layout: options flow inline, breaking between (not inside)
    return entry.options.enumerate().map(p => {
      let deco = deco-of(p.at(1))
      box({
        deco("(" + LETTERS.at(p.at(0)) + ") ")
        deco(p.at(1).body)
        if key and p.at(1).correct { text(fill: key-color, weight: "bold", " ✓") }
      })
    }).join(h(1.6em, weak: true))
  }
  let cells = entry.options.enumerate().map(p => {
    let j = p.at(0)
    let o = p.at(1)
    let deco = deco-of(o)
    grid(
      columns: (1.8em, 1fr),
      column-gutter: 0.3em,
      deco("(" + LETTERS.at(j) + ")"),
      {
        deco(o.body)
        if key and o.correct { text(fill: key-color, weight: "bold", " ✓") }
      },
    )
  })
  grid(
    columns: (1fr,) * entry.q.columns,
    row-gutter: 0.6em,
    column-gutter: 1em,
    ..cells,
  )
}

// Keep `body` on one page: if it does not fit in the space left, it moves to the
// next page whole. Content taller than a full page is left breakable (an
// unbreakable over-tall block would run off the page and be cut in print).
// context content is transparent to pagination (unlike layout(), whose
// implicit container would clip); page geometry matches exam-doc's set rule.
#let _keep(body) = context {
  let avail-w = page.width - 4cm
  let avail-h = page.height - 4.6cm
  let h = measure(block(width: avail-w, body)).height
  if h > avail-h { body } else { block(breakable: false, body) }
}

// Empty writing space of a fixed height. Unlike v(), it is never cut short at
// the bottom of a page (spacing is discarded at page breaks; a block is not).
#let _space(h) = block(width: 100%, height: h, breakable: false, above: 0pt, below: 0pt)

// Hidden, referable anchor for a labelled question ("qf-question") or
// subquestion ("qf-part"); the show rules in exam-doc hide it and print
// references to it as "Q3", "(c)" or "Q3(c)".
#let _anchor(kind, lab, qno, part) = if lab != none {
  [#figure(kind: kind, supplement: none, numbering: "1", outlined: false, metadata((qno: qno, part: part)))#lab]
}

#let _ref-text(it) = {
  let el = it.element
  if el == none or el.func() != figure or el.kind not in ("qf-question", "qf-part") { return it }
  let d = el.body.value
  let here = cur-q-state.get()
  let t = if d.part == none { "Q" + str(d.qno) }
    else if here == d.qno { "(" + d.part + ")" }
    else { "Q" + str(d.qno) + "(" + d.part + ")" }
  link(el.location(), t)
}

#let _render-question(entry, key, show-marks: true) = {
  let q = entry.q
  let inner = {
    // Arm the bank-style blank() machinery for this question (and disarm it
    // otherwise, so a stray answer-less blank() fails loudly).
    if q.type == "fill_blank" {
      blank-counter.update(0)
      q-state.update((id: q.id, answers: q.answers, width: q.blank-width, key: key))
    } else {
      blank-counter.update(0)
      q-state.update(none)
    }
    cur-q-state.update(entry.qno)
    // with subquestions, the stem travels with part (a) instead of being
    // stranded at the bottom of a page
    block(sticky: q.at("parts", default: ()).len() > 0, grid(
      columns: (2.4em, 1fr, auto),
      column-gutter: 0.6em,
      strong("Q" + str(entry.qno) + "."),
      {
        _anchor("qf-question", q.at("label", default: none), entry.qno, none)
        q.body
        if q.type == "mcq" and q.multiple {
          h(0.35em)
          text(size: 10pt, emph[(Select all that apply.)])
        }
      },
      if show-marks { marks-tag(q.marks) },
    ))
    let parts = q.at("parts", default: ())
    let part-marks = parts.len() > 0 and parts.all(p => p.marks != none)
    for (pi, p) in parts.enumerate() { _keep({
      block(inset: (left: 2.4em), above: 0.8em, grid(
        columns: (2em, 1fr, auto),
        column-gutter: 0.6em,
        "(" + "abcdefghijklmnopqrstuvwxyz".at(pi) + ")",
        {
          _anchor("qf-part", p.at("label", default: none), entry.qno, "abcdefghijklmnopqrstuvwxyz".at(pi))
          p.body
        },
        if show-marks and part-marks { marks-tag(p.marks) },
      ))
      if q.type == "subjective" and p.space != auto {
        if key {
          if p.model != none {
            block(inset: (left: 4.4em), above: 0.7em, key-note("Model answer", p.model, rgb("#eef7f0"), key-color))
          }
          if p.rubric != none {
            block(inset: (left: 4.4em), above: 0.7em, key-note("Rubric", p.rubric, luma(246), luma(120)))
          }
        } else if p.space != none {
          _space(p.space)
        }
      }
    }) }
    if q.type == "fill_blank" {
      context {
        let n = blank-counter.get().first()
        assert(
          n == q.answers.len(),
          message: q.id + ": body has " + str(n) + " blank marker(s) but "
            + str(q.answers.len()) + " answer(s)",
        )
      }
    }
    if q.type == "mcq" {
      block(inset: (left: 2.4em), above: 0.7em, _render-options(entry, key))
      if key and q.explanation != none {
        block(inset: (left: 2.4em), above: 0.8em, key-note("Explanation", q.explanation, rgb("#eef7f0"), key-color))
      }
    } else if q.type == "subjective" {
      if key {
        if q.model-answer != none {
          block(inset: (left: 2.4em), above: 0.8em, key-note("Model answer", q.model-answer, rgb("#eef7f0"), key-color))
        }
        if q.rubric != none {
          block(inset: (left: 2.4em), above: 0.8em, key-note("Rubric", q.rubric, luma(246), luma(120)))
        }
      } else if q.answer-space != none {
        _space(q.answer-space)
      }
    }
  }
  // A question with subquestions may break between parts (each part, with its
  // answer space, is kept whole above); anything else is kept whole.
  if q.at("parts", default: ()).len() > 0 { inner } else { _keep(inner) }
}

#let _answer-grid(mcqs, key) = {
  for chunk in mcqs.chunks(12) {
    block(
      above: 0.7em,
      table(
        columns: (auto,) + (2.3em,) * chunk.len(),
        align: center + horizon,
        stroke: 0.6pt,
        inset: 4pt,
        text(size: 9pt, weight: "bold", "Q"),
        ..chunk.map(e => text(size: 9pt, str(e.qno))),
        text(size: 9pt, weight: "bold", "Ans"),
        ..chunk.map(e => if key {
          // multi-select answers can be 3+ letters; shrink to fit the cell
          text(fill: key-color, weight: "bold", size: if e.answer.len() > 2 { 7pt } else { 9pt }, e.answer)
        } else {
          v(1.3em)
        }),
      ),
    )
  }
}

// Student answer sheet: numbered rows in column-major order (1..25 down the
// first column, 26..50 down the second), on a page of its own.
//   style "boxes": a lettered box per option, to shade/tick
//   style "write": one empty box per question, to write the letter(s)
#let _answer-sheet(mcqs, key, exam, set-id, show-set, style: "boxes", cols: 2, choices: auto, page: true, title: auto, group: 5) = {
  assert(group == none or (type(group) == int and group >= 1), message: "answer-sheet: group must be a positive integer or none")
  assert(style in ("boxes", "write"), message: "answer-sheet must be none, \"boxes\" or \"write\"")
  assert(type(cols) == int and cols >= 1, message: "answer-sheet-columns must be a positive integer")
  let nch = if choices == auto { calc.max(..mcqs.map(e => e.options.len())) } else { choices }
  assert(
    type(nch) == int and mcqs.all(e => e.options.len() <= nch),
    message: "answer-sheet-choices (" + repr(nch) + ") is smaller than the number of options in some question",
  )
  let rows = calc.ceil(mcqs.len() / cols)
  let cell = 1.4em
  let row(e) = {
    let num = text(weight: "bold", str(e.qno) + ".")
    if style == "boxes" {
      (num, ..range(nch).map(j => {
        let L = LETTERS.at(j)
        let ticked = key and L in e.answer
        if j < e.options.len() {
          // letters are printed once, in a header row above each column
          box(width: cell, height: cell, stroke: if ticked { 1pt + key-color } else { 0.6pt },
            if ticked { align(center + horizon, text(size: 11pt, weight: "bold", fill: key-color, "✓")) })
        } else { [] }
      }))
    } else {
      (num, box(width: 3.2em, height: cell, stroke: 0.6pt,
        align(center + horizon, if key { text(fill: key-color, weight: "bold", e.answer) })))
    }
  }
  let column(chunk) = grid(
    columns: if style == "boxes" { (2.4em, 0.3em) + (cell,) * nch } else { (2.4em, 0.3em, auto) },
    column-gutter: 3pt,
    row-gutter: 5pt,
    align: (right + horizon, horizon) + (center + horizon,) * nch,
    ..(if style == "boxes" {
      ([], []) + range(nch).map(j => text(size: 9pt, weight: "bold", LETTERS.at(j)))
    } else { () }),
    ..chunk.enumerate().map(((i, e)) => {
      let r = row(e)
      let cells = (r.first(), []) + r.slice(1)
      // a thin rule under every `group` rows (not after the column's last row)
      if group != none and calc.rem(i + 1, group) == 0 and i + 1 < chunk.len() {
        cells.push(grid.cell(colspan: cells.len(), line(length: 100%, stroke: 0.5pt + luma(150))))
      }
      cells
    }).flatten(),
  )
  if page {
    pagebreak(weak: true)
    align(center)[
      #text(size: 12pt, weight: "bold", exam.at("course", default: "")) \
      #text(size: 14pt, weight: "bold")[#if title == auto [#exam.at("title", default: exam.id) — Answer Sheet] else [#title]]
      #if key [#linebreak() #text(size: 13pt, weight: "bold", fill: rgb("#b3261e"))[Solution]]
      #if show-set { h(1em); box(stroke: 1pt, inset: (x: 8pt, y: 4pt), radius: 2pt, text(weight: "bold", "SET " + set-id)) }
    ]
    if not key and exam.at("name-line", default: true) {
      v(6pt)
      grid(
        columns: (auto, 1fr, auto, 0.6fr),
        column-gutter: 8pt,
        align: bottom,
        [Name:], line(length: 100%, stroke: 0.7pt),
        [Student ID:], line(length: 100%, stroke: 0.7pt),
      )
    }
  } else {
    v(1em, weak: true)
    text(size: 12pt, weight: "bold", if title == auto [MCQ Answer Sheet] else { title })
    if key { linebreak(); text(size: 12pt, weight: "bold", fill: rgb("#b3261e"))[Solution] }
  }
  v(4pt)
  align(center, text(size: 9.5pt, style: "italic", if style == "boxes" {
    [Tick (✓) the box of your answer for each question.]
  } else {
    [Write the letter of your answer in the box for each question.]
  }))
  v(2pt)
  line(length: 100%, stroke: 0.5pt)
  align(center, grid(
    columns: cols,
    column-gutter: 3em,
    ..mcqs.chunks(rows).map(column),
  ))
  if page { pagebreak(weak: true) }
}

// Render one placed #answer-sheet(...) marker (o = its options).
#let _placed-sheet(R, key, exam, set-id, show-set, o) = {
  let secs = if o.parts == auto { range(R.sections.len()) } else {
    let ps = if type(o.parts) == int { (o.parts,) } else { o.parts }
    for p in ps {
      assert(type(p) == int and p >= 1 and p <= R.sections.len(),
        message: "answer-sheet(parts: ...): part numbers run 1.." + str(R.sections.len()) + ", got " + repr(p))
    }
    ps.map(p => p - 1)
  }
  let mcqs = secs.map(i => R.sections.at(i).questions).flatten().filter(e => e.type == "mcq")
  assert(mcqs.len() > 0, message: "answer-sheet(): the selected parts have no multiple-choice questions")
  let sheet = _answer-sheet(mcqs, key, exam, set-id, show-set, style: o.style, cols: o.columns,
    choices: o.choices, page: o.page, title: o.title, group: o.group)
  // inline sheets move to the next page whole rather than splitting their columns
  if o.page { sheet } else { block(breakable: false, width: 100%, above: 1.2em, sheet) }
}

// Grader's score table on the cover, built after shuffling so it matches this set.
//   "parts":     one column per part
//   "questions": one column per question
//   "mixed":     shuffled parts get one column; unshuffled parts one column per question
#let _grade-table(R, by) = {
  // A part made only of MCQs is labelled "MC" when it is the only such part;
  // otherwise parts keep their letters (Part A, Part B, ...).
  let all-mc = R.sections.map(s => s.questions.all(e => e.type == "mcq"))
  let mc-label = all-mc.filter(x => x).len() == 1
  let cols = ()
  for (i, s) in R.sections.enumerate() {
    if by == "questions" or (by == "mixed" and not s.shuffle) {
      for e in s.questions { cols.push(([Q#e.qno], e.marks)) }
    } else {
      cols.push((if mc-label and all-mc.at(i) [MC] else [Part #numbering("A", i + 1)], s.marks))
    }
  }
  cols.push(([Total], R.total))
  let n = cols.len()
  let last = n - 1
  let head-fill = luma(238)
  let line-c = luma(150)
  // score cell: room to write, with the maximum in the bottom-right corner
  let score-cell(m, bold: false) = box(width: 100%, height: 3.4em, {
    place(bottom + right, dx: -1pt, dy: -1pt,
      text(size: 8.5pt, fill: luma(110), weight: if bold { "bold" } else { "regular" }, "/ " + str(m)))
  })
  block(width: 100%, above: 1.2em, align(center, context {
    text(size: 8.5pt, fill: luma(110), tracking: 0.04em, smallcaps[For grader use only])
    v(0.3em)
    table(
      // equal-width columns (wide enough for the longest label); Total a bit wider
      columns: {
        let lab = c => text(size: 10.5pt, weight: "bold", c.at(0))
        let w = calc.max(4.4em.to-absolute(), ..cols.map(c => measure(lab(c)).width + 16pt))
        (w,) * last + (w + 0.8em.to-absolute(),)
      },
      inset: (x: 6pt, y: 4pt),
      align: center + horizon,
      stroke: (x, y) => (
        left: if x > 0 { 0.4pt + line-c } else { 0.8pt + luma(60) },
        right: if x == last { 0.8pt + luma(60) } else { none },
        top: if y == 0 { 0.8pt + luma(60) } else { 0.4pt + line-c },
        bottom: if y == 1 { 0.8pt + luma(60) } else { none },
      ),
      fill: (x, y) => if y == 0 { if x == last { luma(215) } else { head-fill } } else if x == last { luma(248) },
      ..cols.map(c => text(size: 10.5pt, weight: "bold", c.at(0))),
      ..cols.enumerate().map(((j, c)) => score-cell(c.at(1), bold: j == last)),
    )
  }))
}

#let exam-doc(config, set-id, mode) = {
  assert(mode == "exam" or mode == "key", message: "mode must be 'exam' or 'key', got: " + mode)
  let key = mode == "key"
  let exam = config.exam
  let R = realize(config, set-id)
  let all-qs = R.sections.map(s => s.questions).flatten()
  let mcqs = all-qs.filter(e => e.type == "mcq")
  let show-grid = exam.at("answer-grid", default: false) and mcqs.len() > 0
  let show-marks = exam.at("show-marks", default: true)
  let show-set = exam.at("show-set", default: true)
  let sheet = exam.at("answer-sheet", default: none)
  let placed = exam.at("sheets", default: ())
  let show-sheet = (sheet != none and mcqs.len() > 0) or placed.len() > 0
  // placed items: #answer-sheet(...) markers, or raw content such as #pagebreak()
  let sheets-at(slot) = placed.filter(x => x.slot == slot).map(x => {
    if "raw" in x.v { x.v.raw } else { _placed-sheet(R, key, exam, set-id, show-set, x.v) }
  }).join()
  let sheet-at = exam.at("answer-sheet-at", default: "end")
  assert(sheet-at in ("start", "end"), message: "answer-sheet-at must be \"start\" or \"end\"")
  let sheet-doc = if sheet != none and mcqs.len() > 0 {
    _answer-sheet(mcqs, key, exam, set-id, show-set, style: sheet,
      cols: exam.at("answer-sheet-columns", default: 2),
      choices: exam.at("answer-sheet-choices", default: auto),
      group: exam.at("answer-sheet-group", default: 5))
  }

  let instr = ()
  if exam.at("name-line", default: true) { instr.push([Write your name and student ID before starting.]) }
  instr += (
    [This paper has #all-qs.len() #if all-qs.len() == 1 [question] else [questions]#if R.sections.len() > 1 [ in #R.sections.len() parts]#if show-marks [, for a total of #R.total marks].],
  )
  if show-grid and not key {
    instr.push([Record your final MCQ answers in the answer grid below — the grid is what gets graded.])
  }
  if show-sheet and not key {
    instr.push([Record your multiple-choice answers on the answer sheet — only the answer sheet is graded.])
  }
  let extra = exam.at("instructions", default: ())
  let show-instr = extra != none
  if show-instr { for s in extra { instr.push(s) } }

  let info = ()
  if "date" in exam { info.push([Date: #exam.date]) }
  if "duration" in exam { info.push([Duration: #exam.duration]) }
  if show-marks { info.push([Maximum marks: #R.total]) }

  // Default page furniture; both are overridable via exam.header / exam.footer
  // (auto = these defaults, none = off, content = fixed, function = called
  // with (exam, set, mode, total) and may itself use `context`).
  let default-header = context {
    if counter(page).get().first() > 1 {
      grid(
        columns: (1fr, auto),
        text(size: 9pt, fill: gray.darken(30%), {
          exam.at("course", default: "")
          " — "
          exam.at("title", default: "")
        }),
        if show-set { text(size: 9pt, weight: "bold", "SET " + set-id) },
      )
      v(-4pt)
      line(length: 100%, stroke: 0.4pt + gray)
    }
  }
  let default-footer = context {
    let p = counter(page).get().first()
    let t = counter(page).final().first()
    align(
      center,
      text(size: 9pt, fill: gray.darken(30%), (if show-set { "Set " + set-id + "  ·  " } else { "" }) + "Page " + str(p) + " of " + str(t)),
    )
  }
  let resolve = (v, default) => {
    if v == auto { default } else if type(v) == function {
      v((exam: exam, "set": set-id, mode: mode, total: R.total))
    } else { v }
  }

  [
    #set document(title: plaintext(exam.at("title", default: exam.id)) + (if show-set { " — Set " + set-id } else { "" }) + (if key { " (Solution)" } else { "" }))
    #set page(
      paper: "a4",
      margin: (x: 2cm, top: 2.3cm, bottom: 2.3cm),
      header: resolve(exam.at("header", default: auto), default-header),
      footer: resolve(exam.at("footer", default: auto), default-footer),
    )
    #set text(font: "New Computer Modern", size: 11pt)
    #set par(justify: true)
    #show figure.where(kind: "qf-question"): none
    #show figure.where(kind: "qf-part"): none
    #show ref: it => context _ref-text(it)
    #mode-state.update(mode)
    #metadata(meta-of(R)) <answerkey>

    #align(center)[
      #text(size: 13pt, weight: "bold", exam.at("course", default: "")) \
      #v(1pt)
      #text(size: 16pt, weight: "bold")[#exam.at("title", default: exam.id)] \
      #if key [#text(size: 15pt, weight: "bold", fill: rgb("#b3261e"))[Solution] #linebreak()]
      #v(4pt)
      #text(size: 10.5pt, info.join(h(2.2em)))
      #v(6pt)
      #if show-set { box(stroke: 1.2pt, inset: (x: 14pt, y: 7pt), radius: 2pt, text(size: 14pt, weight: "bold", "SET " + set-id)) }
    ]

    #if not key and exam.at("name-line", default: true) {
      v(8pt)
      grid(
        columns: (auto, 1fr, auto, 0.45fr),
        column-gutter: 8pt,
        align: bottom,
        [Name:], line(length: 100%, stroke: 0.7pt),
        [Student ID:], line(length: 100%, stroke: 0.7pt),
      )
    }

    #if show-instr { block(
      width: 100%,
      stroke: 0.6pt + gray.darken(20%),
      inset: 9pt,
      radius: 2pt,
      above: 1em,
      {
        text(size: 10.5pt, weight: "bold", "Instructions")
        v(3pt)
        set text(size: 10pt)
        list(spacing: 0.55em, ..instr)
      },
    ) }

    #{
      let gt = exam.at("grade-table", default: none)
      assert(gt in (none, "parts", "questions", "mixed"),
        message: "grade-table must be none, \"parts\", \"questions\" or \"mixed\"")
      if gt != none and not key { _grade-table(R, gt) }
    }

    #if show-grid {
      block(above: 1em, {
        text(size: 10.5pt, weight: "bold", "MCQ Answer Grid")
        _answer-grid(mcqs, key)
      })
    }

    #if exam.at("cover-page", default: false) { pagebreak(weak: true) }
    #if sheet-doc != none and sheet-at == "start" { sheet-doc }

    #for (si, s) in R.sections.enumerate() {
      sheets-at(si)
      if s.title != none {
        block(above: 1.6em, below: 0.4em, sticky: true, {
          grid(
            columns: (1fr, auto),
            text(size: 12.5pt, weight: "bold")[Part #numbering("A", si + 1) — #s.title],
            if show-marks { text(size: 10pt, style: "italic", fill: gray.darken(40%))[#s.marks marks] },
          )
          if s.instructions != none {
            v(2pt)
            text(size: 10pt, style: "italic", s.instructions)
          }
          v(3pt)
          line(length: 100%, stroke: 0.5pt)
        })
      } else if s.instructions != none {
        block(above: 1.2em, below: 0.4em, text(size: 10pt, style: "italic", s.instructions))
      }
      for (qi, e) in s.questions.enumerate() {
        if e.q.at("new-page", default: false) or (s.at("new-page", default: false) and qi > 0) {
          pagebreak(weak: true)
        }
        block(above: 1.1em, _render-question(e, key, show-marks: show-marks))
      }
    }

    #v(1.5em)
    #align(center, text(size: 10pt, style: "italic", "— End of paper —"))
    #if sheet-doc != none and sheet-at == "end" { sheet-doc }
    #sheets-at(R.sections.len())
  ]
}

// Entry point shared by both authoring styles. Reads set + mode from --input
// so one source file serves every set:
//
//   typst compile exam.typ set-B.pdf --root . --input set=B --input mode=key
//
#let make-exam(exam: none, questions: (), sections: (), default-mode: "exam") = {
  assert(type(exam) == dictionary and "id" in exam, message: "make-exam needs exam: (id: \"...\", ...)")
  assert(
    type(exam.id) == str and exam.id.match(regex("^[A-Za-z0-9._-]+$")) != none,
    message: "exam id must be a slug of letters/digits/._- (it seeds the shuffles and names the output files), got: " + repr(exam.id),
  )
  let sets = exam.at("sets", default: ("A",))
  if type(sets) == str { sets = (sets,) }
  assert(sets.len() > 0, message: "exam.sets must not be empty")
  assert(sets.dedup().len() == sets.len(), message: "exam.sets contains duplicates")
  let exam = exam
  exam.insert("sets", sets)
  let set-id = sys.inputs.at("set", default: str(sets.first()))
  assert(str(set-id) in sets.map(str), message: "unknown set '" + set-id + "'; exam.sets = " + repr(sets))
  exam-doc(
    (exam: exam, questions: questions, sections: sections),
    set-id,
    sys.inputs.at("mode", default: default-mode),
  )
}
