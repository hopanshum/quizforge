// Plain-markup front-end: `#show: quiz.with(...)` turns an ordinary Typst
// document into a randomizable exam by walking its content tree.
//
//   = Part heading            → section (content before the first question
//                               becomes the section's instructions)
//   + question body           → question (enum item)
//     - option                → MCQ option (list item); ✓ or #yes marks correct
//   #blank[ans] in the body   → fill-in-the-blank question
//   #answer(6cm)[model]       → subjective question
//   #m(2) #qid(..) #opts(..) #explain[..] #pin — invisible markers
//
// Question type is inferred: options present → mcq; blanks present → fib;
// otherwise subjective. "None/All/Both of the above" options auto-pin last;
// two or more ✓ options auto-enable multi-select.

#import "rng.typ": fnv1a
#import "base.typ": plaintext
#import "model.typ": mcq, fib, subj, opt
#import "render.typ": make-exam

// Accepted correct-option prefixes (plain ✓ and heavy ✔).
#let _CHECKS = ("✓", "✔")

// If t starts with a checkmark, return the remainder (trimmed); else none.
#let _strip-prefix(t) = {
  for c in _CHECKS {
    if t.starts-with(c) { return t.slice(c.len()).trim(at: start) }
  }
  none
}

// The value dict of a quizforge marker, or none.
#let _marker(c) = {
  if type(c) == content and c.func() == metadata and type(c.value) == dictionary and "qf" in c.value {
    c.value
  } else {
    none
  }
}

#let _children(c) = if c.has("children") { c.children } else { (c,) }

// Flatten the top-level stream: unwrap nested sequences (produced by
// #include, letting large quizzes span multiple files) and reject styled
// wrappers (a #set/#show inside the body would silently swallow everything
// after it — set rules belong above the `#show: quiz` line, where they
// apply to the whole rendered paper).
#let _flat-children(body) = {
  let out = ()
  for c in _children(body) {
    if type(c) != content {
      out.push(c)
    } else if repr(c.func()) == "sequence" {
      out += _flat-children(c)
    } else if repr(c.func()) == "styled" {
      assert(
        false,
        message: "quizforge: #set/#show rules inside the quiz body are not supported — move them above the '#show: quiz' line (they will then style the whole paper)",
      )
    } else {
      out.push(c)
    }
  }
  out
}

#let _is-blankish(c) = repr(c.func()) in ("space", "parbreak", "linebreak")

// Recursively collect quizforge markers, without descending into list/enum
// items (those belong to nested scopes). Walks EVERY content-valued field —
// not just body/children — so markers survive inside equations (attach
// scripts, fractions), figures, tables, styled wrappers, etc.
#let _collect-markers(c, out) = {
  let mk = _marker(c)
  if mk != none { out.push(mk); return out }
  if type(c) != content or c.func() in (list.item, enum.item) { return out }
  for pair in c.fields().pairs() {
    let v = pair.at(1)
    if type(v) == content {
      out = _collect-markers(v, out)
    } else if type(v) == array {
      for x in v {
        if type(x) == content { out = _collect-markers(x, out) }
      }
    }
  }
  out
}

// Labels: `<name>` after a question's or subquestion's text makes it
// referable with `@name`. Typst attaches a label to the element just before it
// (usually a text node, which cannot be referenced), so the parser takes the
// label off that element and the renderer re-attaches it to a hidden anchor.
// Elements Typst can already reference keep their labels.
#let _NATIVE-REF = (math.equation, figure, heading, footnote)

#let _unlabel(c, where) = {
  let f = c.func()
  if f == text { return text(c.text) }
  if f == metadata { return metadata(c.value) }
  if f == strong or f == emph { return f(c.body) }
  if f == smartquote { return smartquote(double: c.at("double", default: true)) }
  assert(
    false,
    message: where + ": the label " + repr(c.label) + " is attached to " + repr(f)
      + " — put a question's or subquestion's <label> right after its text",
  )
}

// (label or none, children with that label removed)
#let _take-label(children, where) = {
  let lab = none
  let out = ()
  for c in children {
    if type(c) == content and c.has("label") and c.func() not in _NATIVE-REF {
      assert(
        lab == none,
        message: where + ": more than one <label> (" + repr(lab) + " and " + repr(c.label) + ")",
      )
      lab = c.label
      out.push(_unlabel(c, where))
    } else {
      out.push(c)
    }
  }
  (lab, out)
}

// Detect and strip a leading ✓/✔ from an option body. Returns (found, body).
#let _strip-check(body) = {
  if body.has("text") {
    let rest = _strip-prefix(body.text)
    if rest != none { return (true, text(rest)) }
    return (false, body)
  }
  if body.has("children") {
    let ch = body.children
    let i = 0
    // scan past whitespace AND invisible markers (#pin ✓ Foo must still work)
    while i < ch.len() and (_is-blankish(ch.at(i)) or ch.at(i).func() == metadata) { i += 1 }
    if i < ch.len() and ch.at(i).has("text") {
      let rest = _strip-prefix(ch.at(i).text)
      if rest != none {
        let head = ch.slice(0, i)
        let tail = ch.slice(i + 1)
        if rest == "" {
          // the ✓ was its own word — also swallow the following space
          if tail.len() > 0 and _is-blankish(tail.first()) { tail = tail.slice(1) }
          return (true, (head + tail).join())
        }
        return (true, (head + (text(rest),) + tail).join())
      }
    }
  }
  (false, body)
}

#let _NOTA = regex("^\s*(none|all|both) of the above")

// Marker kind → the function the author typed, for error messages.
#let _MARKER-NAMES = (
  marks: "m(...)", id: "qid(...)", opts: "opts(...)", explain: "explain[...]",
  answer: "answer(...)", blank: "blank[...]", sec: "section(...)", sheet: "answer-sheet(...)",
  correct: "yes", fixed: "pin",
)

#let _parse-option(li, where) = {
  let correct = false
  let fixed = none
  for mk in _collect-markers(li.body, ()) {
    if mk.qf == "correct" { correct = true }
    else if mk.qf == "fixed" { fixed = mk.v }
    else {
      assert(
        false,
        message: where + ": #" + _MARKER-NAMES.at(mk.qf, default: mk.qf)
          + " cannot appear inside an option — only ✓ / #yes / #pin belong there",
      )
    }
  }
  let stripped = _strip-check(li.body)
  if stripped.at(0) { correct = true }
  let body = stripped.at(1)
  // Reject truly empty options ("- ✓" alone) but allow content whose text is
  // statically opaque (context-based package output such as unify's qty()).
  let is-empty = (
    body == none or body == []
      or (type(body) == content and body.has("text") and body.text.trim() == "")
  )
  assert(not is-empty, message: where + ": an option is empty")
  if fixed == none and lower(plaintext(body)).match(_NOTA) != none {
    fixed = "last" // "None of the above" and friends auto-pin to the end
  }
  opt(correct: correct, fixed: fixed, body)
}

#let _build-question(item, where, default-space) = {
  let markers = ()
  let option-items = ()
  let body-parts = ()
  let sub-items = () // nested `+` items = subquestions (a), (b), ...
  for c in _children(item.body) {
    if type(c) == content and c.func() == list.item {
      option-items.push(c)
    } else if type(c) == content and c.func() == enum.item {
      sub-items.push(c)
    } else if sub-items.len() > 0 {
      assert(
        not _collect-markers(c, ()).any(mk => mk.qf == "answer"),
        message: where + ": #answer(...) after the subquestions is at the question's indentation, so it "
          + "would print once after all parts. To put it right after a subquestion, indent it under that "
          + "subquestion's text (4 spaces). For one shared answer box after all parts, put #answer(...) "
          + "in the stem, before the first '+' subquestion.",
      )
      assert(
        _is-blankish(c) or _marker(c) != none,
        message: where + ": text after the subquestions is not supported — put it in the question "
          + "stem (above the first '+' subquestion) or inside the last subquestion",
      )
      markers = _collect-markers(c, markers)
    } else {
      markers = _collect-markers(c, markers)
      body-parts.push(c)
    }
  }
  // Subquestions: each may carry its own #m, #answer and #blank markers.
  let parts = ()
  for (pi, si) in sub-items.enumerate() {
    let pwhere = where + ", part (" + "abcdefghijklmnopqrstuvwxyz".at(pi) + ")"
    let (plab, pch) = _take-label(_children(si.body), pwhere)
    let p = (
      body: if plab == none { si.body } else { pch.join() },
      marks: none, space: auto, model: none, rubric: none, blanks: (), label: plab,
    )
    for mk in _collect-markers(si.body, ()) {
      if mk.qf == "marks" {
        assert(p.marks == none, message: pwhere + ": #m(...) appears more than once")
        p.marks = mk.v
      } else if mk.qf == "answer" {
        assert(p.space == auto, message: pwhere + ": #answer(...) appears more than once")
        p.space = mk.space
        p.model = mk.model
        p.rubric = mk.rubric
      } else if mk.qf == "blank" {
        p.blanks.push(mk.answer)
      } else {
        assert(
          false,
          message: pwhere + ": only #m(...), #answer(...) and #blank[...] can go inside a subquestion — #"
            + _MARKER-NAMES.at(mk.qf, default: mk.qf) + " belongs on the main question",
        )
      }
    }
    parts.push(p)
  }
  let (qlab, body-parts) = _take-label(body-parts, where)
  while body-parts.len() > 0 and _is-blankish(body-parts.last()) {
    let _ = body-parts.pop() // discard: pop's return value must not join the result
  }
  let body = body-parts.join()
  assert(body != none and plaintext(body).trim() != "", message: where + ": question has no body text")

  // Word-habit blanks: `____` parses as emph(body: []) and renders as NOTHING.
  let has-empty-em(c) = {
    let rec(c, self) = {
      if type(c) != content { return false }
      if repr(c.func()) in ("emph", "strong") and c.at("body", default: none) == [] { return true }
      for pair in c.fields().pairs() {
        let v = pair.at(1)
        if type(v) == content and self(v, self) { return true }
        if type(v) == array {
          for x in v { if type(x) == content and self(x, self) { return true } }
        }
      }
      false
    }
    rec(c, rec)
  }
  assert(
    not has-empty-em(body),
    message: where + ": found underscore-style blanks (____) — in Typst, underscores "
      + "toggle italics and render as nothing; write blanks as #blank[the answer]",
  )

  let marks = 1
  let id = none
  let explanation = none
  let ans-mk = none
  let blanks = ()
  let over = (:)
  let seen-mk = ()
  for mk in markers {
    if mk.qf in ("marks", "id", "explain", "answer", "opts") {
      // repeated #m / #qid / #answer / #opts / #explain on one question is
      // always an authoring accident — the loser would win silently
      assert(
        mk.qf not in seen-mk,
        message: where + ": #" + _MARKER-NAMES.at(mk.qf) + " appears more than once",
      )
      seen-mk.push(mk.qf)
    }
    if mk.qf == "marks" { marks = mk.v }
    else if mk.qf == "id" { id = mk.v }
    else if mk.qf == "explain" { explanation = mk.v }
    else if mk.qf == "answer" { ans-mk = mk }
    else if mk.qf == "blank" { blanks.push(mk.answer) }
    else if mk.qf == "opts" { over = mk.v }
    else if mk.qf == "correct" or mk.qf == "fixed" {
      assert(false, message: where + ": ✓ / #yes / #pin belong on options (- lines), not in the question body")
    }
    else if mk.qf == "sec" {
      assert(false, message: where + ": #section(...) belongs in a part heading, not in a question")
    }
    else if mk.qf == "sheet" {
      assert(false, message: where + ": " + (if "raw" in mk.v { "#insert[...]" } else { "#answer-sheet(...)" })
        + " goes between parts (or at the start/end of the paper), not inside a question")
    }
  }
  if parts.len() > 0 {
    assert(option-items.len() == 0, message: where + ": a multiple-choice question cannot have '+' subquestions")
    let with-m = parts.filter(p => p.marks != none).len()
    assert(
      with-m == 0 or with-m == parts.len(),
      message: where + ": give every subquestion a #m(...) or none of them",
    )
    if with-m > 0 {
      let total = calc.round(parts.map(p => p.marks).sum(), digits: 4)
      assert(
        "marks" not in seen-mk or calc.abs(marks - total) < 1e-9,
        message: where + ": #m(" + str(marks) + ") on the question disagrees with its subquestions, which add up to " + str(total),
      )
      marks = total
    }
    for p in parts { blanks += p.blanks }
  }
  if id == none {
    // Stable identity from the question's own text: reordering/inserting
    // questions never reshuffles others; editing THIS question's wording
    // reshuffles only its own options. Freeze with #qid("...") if needed.
    id = "q" + str(fnv1a(plaintext(body)))
  }

  let q = if option-items.len() > 0 {
    assert(blanks.len() == 0, message: where + ": a question cannot have both options and #blank[...]")
    assert(
      ans-mk == none,
      message: where + ": #answer(...) is for subjective questions — use #explain[...] on an MCQ",
    )
    assert(option-items.len() >= 2, message: where + ": needs at least 2 options")
    let options = option-items.map(li => _parse-option(li, where))
    let ncorrect = options.filter(o => o.correct).len()
    assert(
      ncorrect > 0,
      message: where + ": no option is marked correct — prefix one with ✓ or #yes"
        + " (if these '-' items are prose rather than options, build them with the #list() function instead)",
    )
    mcq(
      id,
      body,
      options: options,
      marks: marks,
      multiple: over.at("multiple", default: ncorrect > 1),
      shuffle: over.at("shuffle", default: true),
      columns: over.at("columns", default: 1),
      compact: over.at("compact", default: false),
      explanation: explanation,
    )
  } else if blanks.len() > 0 {
    assert(
      ans-mk == none,
      message: where + ": #answer(...) cannot be combined with #blank[...] — blanks carry their own answers",
    )
    assert(explanation == none, message: where + ": #explain[...] is only supported on MCQs")
    assert(
      parts.all(p => p.space == auto),
      message: where + ": #answer(...) inside a subquestion cannot be combined with #blank[...]",
    )
    fib(id, body, answers: blanks, marks: marks, parts: parts)
  } else {
    // A ✓ in a question that has NO options usually means the options were
    // written markdown-style (`* item`) or dedented — and were silently
    // absorbed into the body. Refuse rather than print a wrong paper.
    let ptext = plaintext(body)
    assert(
      not ptext.contains("✓") and not ptext.contains("✔"),
      message: where + ": a ✓ appears in the question text but the question has no options — "
        + "options are '- ' list items indented two spaces under the '+ ' question",
    )
    assert(explanation == none, message: where + ": #explain[...] is only supported on MCQs")
    let space = if ans-mk != none { ans-mk.space }
      else if parts.any(p => p.space != auto) { none } // spaces live under the subquestions
      else { default-space }
    subj(
      id,
      body,
      marks: marks,
      answer-space: space,
      model-answer: if ans-mk != none { ans-mk.model } else { none },
      rubric: if ans-mk != none { ans-mk.rubric } else { none },
      parts: parts,
    )
  }
  q.insert("new-page", over.at("new-page", default: false))
  q.insert("label", qlab)
  q
}

// Split the document body into sections of questions.
// Returns (questions: (..), sections: (..)) ready for make-exam.
#let _parse(body, default-space) = {
  let sections = ()
  let cur = (title: none, shuffle: true, "new-page": false, pre: (), items: ())

  let flush(cur, sections) = {
    if cur.items.len() == 0 {
      assert(
        cur.title == none,
        message: "quizforge: part '" + plaintext(cur.title).trim() + "' has no questions (+ items)",
      )
      assert(
        cur.pre.len() == 0,
        message: "quizforge: content before the first part heading or question is not supported — "
          + "put instructions after a part heading, or pass instructions: (...) to quiz()",
      )
      return sections
    }
    sections.push(cur)
    sections
  }

  let sheets = () // (slot: k, v: options) — rendered before section k (k = #sections: at the end)
  let pending = false // a sheet was placed after questions of the current part
  for c in _flat-children(body) {
    if type(c) != content or _is-blankish(c) { continue }
    let mk = _marker(c)
    if mk != none {
      if mk.qf == "sheet" {
        if cur.items.len() > 0 {
          sheets.push((slot: sections.len() + 1, v: mk.v)) // after the current part
          pending = true
        } else {
          sheets.push((slot: sections.len(), v: mk.v)) // before the current part
        }
      } else if mk.qf == "sec" {
        cur.shuffle = mk.v.at("shuffle", default: true)
        cur.insert("new-page", mk.v.at("new-page", default: false))
      } else {
        // A #m(2) drifting between questions would silently change nothing
        // (the question would keep its default marks) — refuse loudly.
        assert(
          false,
          message: "quizforge: found #" + _MARKER-NAMES.at(mk.qf, default: mk.qf)
            + " outside any question (in instructions or between questions) — markers belong inside a question's + item",
        )
      }
      continue
    }
    if c.func() == pagebreak {
      // #pagebreak() between parts (or at the start/end) is kept where it is
      if cur.items.len() > 0 {
        sheets.push((slot: sections.len() + 1, v: (raw: c)))
        pending = true
      } else {
        sheets.push((slot: sections.len(), v: (raw: c)))
      }
      continue
    }
    if c.func() == heading {
      assert(c.depth == 1, message: "quizforge: only level-1 headings (= Part) are supported")
      pending = false
      sections = flush(cur, sections)
      let title = c.body
      for hm in _collect-markers(c.body, ()) {
        if hm.qf == "sec" { title = c.body } // markers are invisible; keep body as-is
      }
      cur = (title: title, shuffle: true, "new-page": false, pre: (), items: ())
      for hm in _collect-markers(c.body, ()) {
        if hm.qf == "sec" {
          cur.shuffle = hm.v.at("shuffle", default: true)
          cur.insert("new-page", hm.v.at("new-page", default: false))
        }
      }
    } else if c.func() == enum.item {
      assert(
        not pending,
        message: "quizforge: #answer-sheet(...), #insert[...] or #pagebreak() sits between questions of a part — questions there are shuffled, "
          + "so place it before the part heading, after the part's last question, or at the start/end of the paper",
      )
      cur.items.push(c)
    } else {
      // A bare '- item' at part level is almost always a dedented (or
      // swapped +/-) option — silently treating it as prose would be cruel.
      assert(
        c.func() != list.item,
        message: "quizforge: a '- option' appears outside any question — indent options two spaces "
          + "under their '+ question' (questions start with '+', options with '-'; "
          + "for a real bullet list in instructions, use the #list(..) function instead)",
      )
      assert(
        cur.items.len() == 0,
        message: "quizforge: free content between questions is not supported (it cannot move with "
          + "shuffled questions) — fold it into a question body, start it with '+ ' if it is a new "
          + "question, or put it right after the part heading (where it becomes the part's instructions)",
      )
      cur.pre.push(c)
    }
  }
  sections = flush(cur, sections)
  assert(sections.len() > 0, message: "quizforge: no questions found — write questions as + items")

  let questions = ()
  let out-sections = ()
  let seen = (:) // id → where, to explain hash collisions from identical text
  for (si, sec) in sections.enumerate() {
    let ids = ()
    for (qi, item) in sec.items.enumerate() {
      let where = (
        if sec.title == none { "question " + str(qi + 1) }
        else { "question " + str(qi + 1) + " of part '" + plaintext(sec.title).trim() + "'" }
      )
      let q = _build-question(item, where, default-space)
      assert(
        q.id not in seen,
        message: "quizforge: " + where + " and " + seen.at(q.id, default: "?")
          + " are identical (same text or same #qid) — reword one or give it a distinct #qid(...)",
      )
      seen.insert(q.id, where)
      questions.push(q)
      ids.push(q.id)
    }
    out-sections.push((
      title: sec.title,
      instructions: if sec.pre.len() > 0 { sec.pre.join() } else { none },
      use: ids,
      shuffle: sec.shuffle,
      "new-page": sec.at("new-page", default: false),
    ))
  }
  (questions: questions, sections: out-sections, sheets: sheets)
}

// The plain-markup entry point:
//
//   #show: quiz.with(id: "dl-quiz-2", course: "...", sets: ("A", "B"))
//
// Compiled as-is, the master renders the ANSWER KEY (what you wrote, ✓ visible);
// pass --input mode=exam --input set=B for a randomized student paper.
#let quiz(
  id: none,
  course: "",
  title: "",
  date: none,
  duration: none,
  sets: none, // none = one unlabelled paper (set "A" internally)
  seed: none, // any int/string; changes every shuffle. --input seed=... overrides
  show-set: auto, // auto = show "SET X" only when sets are given; true / false to force
  answer-grid: false,
  answer-sheet: none, // none | "boxes" | "write": separate numbered MCQ answer sheet
  answer-sheet-columns: 2,
  answer-sheet-choices: auto, // auto = most options of any MCQ; or an int (e.g. 5 for A–E)
  answer-sheet-group: 5, // thin rule after every 5 rows; none = no rules
  answer-sheet-at: "end", // "start" (own page right after the cover block) | "end"
  cover-page: false, // true = questions start on a new page after the cover
  grade-table: none, // none | "parts" | "questions" | "mixed": grader's score table on the cover
  instructions: (), // extra bullets; none = no Instructions box at all
  answers: true, // false = student paper (like commenting out \printanswers); --input mode=... still overrides
  show-marks: true, // false = hide all marks (per question, per part, cover)
  name-line: true, // false = no Name / Student ID lines
  answer-space: 5cm, // default space for subjective questions without #answer(...); none = no space
  header: auto, // auto = generated | none = off | content | (info) => content
  footer: auto, // ditto; info = (exam, set, mode, total)
  body,
) = {
  assert(
    id != none,
    message: "quizforge: give the quiz an id — #show: quiz.with(id: \"my-quiz-1\", ...)",
  )
  let parsed = _parse(body, answer-space)
  let exam = (
    id: id,
    course: course,
    title: if title == "" { id } else { title },
    sets: if sets == none { ("A",) } else { sets },
    seed: seed,
    "show-set": if show-set == auto { sets != none } else { show-set },
    "answer-grid": answer-grid,
    "answer-sheet": answer-sheet,
    "answer-sheet-columns": answer-sheet-columns,
    "answer-sheet-choices": answer-sheet-choices,
    "answer-sheet-at": answer-sheet-at,
    "answer-sheet-group": answer-sheet-group,
    "grade-table": grade-table,
    "cover-page": cover-page,
    "show-marks": show-marks,
    "name-line": name-line,
    instructions: instructions,
    header: header,
    footer: footer,
  )
  exam.insert("sheets", parsed.sheets)
  if date != none { exam.insert("date", date) }
  if duration != none { exam.insert("duration", duration) }
  make-exam(
    exam: exam,
    questions: parsed.questions,
    sections: parsed.sections,
    default-mode: if answers { "key" } else { "exam" }, // --input mode=... overrides
  )
}
