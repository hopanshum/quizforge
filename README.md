# quizforge

Randomized exam sets from **one plain Typst document**: question order and MCQ
option order shuffle deterministically per set, with auto-generated answer
keys and machine-readable grading metadata. For courses mixing multiple
choice, fill-in-the-blank, and subjective questions.

## Write the paper. That's it.

```typst
#import "@preview/quizforge:0.1.0": *

#show: quiz.with(
  id: "dl-quiz-2",                      // freeze once printed — it seeds the shuffles
  course: "ES 667: Deep Learning",
  title: "Quiz 2 — Optimization",
  sets: ("A", "B", "C", "D"),
  answer-grid: true,
)

= Multiple Choice

Choose the single best answer unless a question says otherwise.

+ #m(2) Adding an L2 penalty $lambda norm(theta)_2^2$ corresponds to which prior?
  - ✓ Gaussian
  - Laplace
  - Uniform
  - None of the above          // auto-pinned to stay last
  #explain[A zero-mean Gaussian prior yields the L2 penalty (L1 ↔ Laplace).]

+ #m(2) Which of the following reduce overfitting?
  - ✓ Dropout
  - ✓ Weight decay             // two ✓ → automatically multi-select
  - Increasing model capacity

= Fill in the Blanks

+ #m(1) Halting training when validation loss stops improving is called
  #blank[early stopping].

= Long Answers #section(shuffle: false)

+ #m(4) Explain why Adam needs bias correction early in training.
  #answer(6cm, rubric: [+2 EMA init at zero; +2 correction factor.])[
    Moment estimates start at zero, so early EMAs are biased toward zero;
    dividing by $1 - beta^t$ corrects this.]
```

**Compiled as-is, this document renders the answer key** — ✓ marks
highlighted, blanks filled, model answers and rubrics shown, the MCQ answer
grid pre-filled. Randomized student papers come from the same file:

```bash
typst compile exam.typ set-B.pdf --input set=B --input mode=exam
```

Each set gets a cover page (set code, name/student ID fields, computed totals and
per-part subtotals, instructions), per-page set headers/footers, and continuous
question numbers. Page furniture is customizable: `quiz.with(header: none)`
turns the header off, `footer: [fixed content]` replaces it, and
`footer: info => [...]` receives `(exam, set, mode, total)` for dynamic
footers. All marks arithmetic is automatic.

## How the randomization works

- `=` headings become parts; `+` items are questions; `-` items are options;
  `✓` (or `#yes`) marks correct ones. Question type is inferred: options →
  MCQ, `#blank[...]` → fill-in-the-blank, otherwise subjective.
- Every set is a **pure function of (quiz id, set id, question text)** — a
  dependency-free seeded PRNG (FNV-1a → xorshift32 → Fisher–Yates), no clocks,
  no OS randomness. Rebuilds are identical, on any machine, forever.
- **Fairness is structural**: every set contains exactly the same questions
  and total marks; only order differs. Section order never changes.
- "None/All/Both of the above" options pin to the last position automatically;
  `#pin` / `#pin-first` pin anything else; `#opts(shuffle: false)` freezes one
  question's options; `#section(shuffle: false)` freezes a part's question order.
- The key and the paper derive from the *same* realized structure — they
  cannot disagree.

## Grading support

Every compiled document embeds a pure-data `<answerkey>` metadata node:

```bash
typst query exam.typ "<answerkey>" --field value --one --input set=B
```

returns question order, correct letters (mapped through each set's
permutation), fill-in answers, marks, and the full option permutation per
question — everything needed to grade or to drive external tooling. The
[repository](https://github.com/nipunbatra/quizforge) ships a
`build.py` that compiles all sets in parallel, re-verifies the fairness
invariants, and writes a combined `answer_key.csv` + SHA-256 manifest.

## Markers reference

| Marker | Meaning |
|--------|---------|
| `#m(2)` | marks for the question (default 1) |
| `✓`, `✔` or `#yes` | correct option |
| `#blank[ans]`, `#blank(width: 3cm)[ans]` | a blank; answer shown only in the key |
| `#answer(6cm)[model]`, `#answer(none, rubric: [...])[...]` | subjective answer space + key-only model answer; `none` prints no space (answer-booklet style) |
| `#explain[...]` | key-only explanation for an MCQ |
| `#pin` / `#pin-first` | pin an option last / first |
| `#opts(shuffle: false, columns: 2, compact: true, multiple: true)` | per-question overrides; `compact` flows options inline to save space |
| `#section(shuffle: false)` | freeze question order in a part |
| `#qid("slug")` | freeze a question's identity (see below) |

Question identity defaults to a hash of the question's own text: reordering or
adding questions never reshuffles the others, and editing one question's
wording reshuffles only *its own* options. Add `#qid("...")` when you want a
question's option order stable across wording edits too.

## Question banks (the second front-end)

For semester-scale reuse, build banks with constructors and select per exam —
same engine, same guarantees, plus filtering and sampling:

```typst
#import "@preview/quizforge:0.1.0": *

#let bank = (
  mcq("conv-params", marks: 2, topic: "cnn", difficulty: "medium",
    [How many parameters does a $3 times 3$ conv, 16→32 channels, with bias have?],
    options: (ans[4640], [4608], [1184], [18464]),
    explanation: [$3 dot 3 dot 16 dot 32 + 32 = 4640$.]),
  // ... hundreds more, across files
)

#make-exam(
  exam: (id: "midsem", course: "…", title: "…", sets: ("A", "B")),
  questions: bank,
  sections: (
    (title: "MCQ", filter: (type: "mcq", difficulty: ("easy", "medium")),
     use: ("conv-params",),   // guaranteed to appear
     pick: 10),               // 10 total — the SAME 10 in every set
  ),
)
```

`pick` sampling is seeded without the set id, so every set gets the same
questions — sampling can never break fairness.

## Plays well with other packages

Question bodies, options, and blank answers are ordinary Typst content, so
third-party packages work inside them — cetz drawings, unify/metro SI units,
physica notation, code blocks, tables. (Answers whose text cannot be extracted
statically, such as context-based `qty(...)`, still render in the key; the
grading CSV shows `(see key)` for them.) Global `#set`/`#show` styling goes
*above* the `#show: quiz` line, where it styles the whole paper.

## Validation = compilation

Structural mistakes fail the build with a message naming the question: no
option marked ✓, a single-option question, a blank/answer mismatch, duplicate
or unknown ids, out-of-range `pick`, free text stranded between shuffled
questions, and more. If it compiles, it's structurally sound — and the student
PDF never embeds the answers.

## License

MIT

## Local fork 0.1.1: grader's score table

`grade-table:` option on `quiz` (student papers only, not the key):

- `none` (default): no table, same as upstream 0.1.0
- `"parts"`: one column per part
- `"questions"`: one column per question (numbers and marks follow this set's shuffle)
- `"mixed"`: a shuffled part gets one column; an unshuffled part (`#section(shuffle: false)`) gets one column per question

```typst
#import "@local/quizforge:0.1.1": *
#show: quiz.with(id: "gt-mid", course: "Game Theory I", title: "Midterm",
  sets: ("A", "B", "C", "D"), grade-table: "mixed")
```

## Local fork 0.1.1: more `quiz()` options

| Option | Default | Effect |
|---|---|---|
| `answers` | `true` | `false` = student paper, like commenting out `\printanswers`. `--input mode=exam/key` on the command line still overrides it. |
| `show-marks` | `true` | `false` = hide marks everywhere: next to questions, next to part titles, on the cover. |
| `instructions` | `()` | Extra bullets for the Instructions box; `none` = no Instructions box at all. |
| `name-line` | `true` | `false` = no Name / Student ID lines. |
| `cover-page` | `false` | `true` = the cover (title, name lines, instructions, grade table) gets its own page; questions start on the next page. |
| `seed` | `none` | Any number or string. Changes every shuffle (question order and option order) while staying reproducible. `--input seed=...` on the command line overrides it. `none` = upstream behaviour (shuffles keyed by `id` alone). |
| `show-set` | `auto` | `auto` = show "SET X" (cover, header, footer, PDF title) only when you pass `sets:`; `true`/`false` to force. |

```typst
#show: quiz.with(id: "PE-I-TA06", course: "Principles of Economics I", title: "TA Session 6",
  answers: false, show-marks: false, instructions: none, name-line: false)
```

## Local fork 0.1.1: MCQ answer sheet

A separate, numbered answer sheet on its own page (column-major: 1–25 down the
left, 26–50 down the right). The key version fills in the correct answers.

| Option | Default | Effect |
|---|---|---|
| `answer-sheet` | `none` | `"boxes"` = a box per option to tick, letters A, B, C… above each column; `"write"` = one empty box to write the letter |
| `answer-sheet-columns` | `2` | number of columns |
| `answer-sheet-choices` | `auto` | boxes per row: `auto` = each question's own option count |
| `answer-sheet-group` | `5` | thin rule after every 5 rows; `none` = no rules |
| `answer-sheet-at` | `"end"` | `"start"` = own page right after the cover; `"end"` = last page (tear-off) |

```typst
#show: quiz.with(id: "pe1-mid", course: "Principles of Economics I", title: "Midterm",
  sets: ("A", "B"), answer-sheet: "boxes", answer-sheet-at: "start")
```

### Placing the sheet yourself: `#answer-sheet(...)`

Instead of the `answer-sheet:` option, write `#answer-sheet(...)` in the body
where you want it: at the very top (right after the cover), between two parts,
or at the end. It can be used more than once.

```typst
#show: quiz.with(id: "pe1-mid", course: "Principles of Economics I", title: "Midterm", sets: ("A", "B"))

#answer-sheet()                     // own page, right after the cover

= Multiple Choice
+ ...

#answer-sheet(parts: 1, page: false, style: "write")   // inline, after Part A

= Problems
+ ...
```

| Argument | Default | Effect |
|---|---|---|
| `style` | `"boxes"` | `"boxes"` or `"write"` |
| `columns` | `2` | number of columns |
| `choices` | `auto` | boxes per row (`auto` = each question's own option count) |
| `page` | `true` | `true` = own page with title and Name / Student ID lines; `false` = inline block (kept whole, moves to the next page if it doesn't fit) |
| `title` | `auto` | custom heading |
| `group` | `5` | thin rule after every 5 rows; `none` = no rules |
| `parts` | `auto` | which parts' MCQs to include: `auto` = all, `1` = Part A, `(1, 3)` = Parts A and C |

It cannot go between two questions of a part (those are shuffled); compilation
fails with a message if you try. To print the sheet separately (different
paper), compile with `--pages`, e.g. `typst compile exam.typ sheet.pdf --pages 2 --input set=A --input mode=exam`.

## Local fork 0.1.1: subquestions

Nested `+` items inside a question become parts (a), (b), (c). Each part can
carry its own `#m(...)`, `#answer(...)` and `#blank[...]`. Give every part a
`#m` (the question's marks become their sum) or none of them (use `#m` on the
question). If any part has `#answer`, the answer space goes under the parts and
no default space is added at the end. Parts keep their order; MCQs cannot have
parts. The stem can be as long as you like (several paragraphs, figures,
tables), indented under the `+`.

```typst
+ Demand is $Q = 100 - P$ and supply is $Q = P$.

  A second paragraph of setup.

  + #m(2) Find the equilibrium price.
    #answer(3cm)[$P^* = 50$.]
  + #m(3) Compute consumer surplus.
    #answer(4cm, rubric: [+1 formula; +2 number.])[$1250$.]
```

## Local fork 0.1.1: page breaks between parts

`#pagebreak()` (with any of its arguments, e.g. `#pagebreak(to: "odd")`) can be
written in the body at the start, between two parts, or at the end. Like
`#answer-sheet()`, it cannot go between two questions of a part.
