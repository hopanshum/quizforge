// Local fork: #insert[...] places free content between parts / at the end.
#import "/lib.typ": *
#show: quiz.with(id: "ins", sets: ("A", "B"))
= Part One
+ #m(1) First question.
  #answer(1cm)[a]
+ #m(1) Second question.
  #answer(1cm)[b]
#insert[INTERLUDE-TEXT]
= Part Two
+ #m(1) Third question.
  #answer(1cm)[c]
#insert[
  #pagebreak()
  = Heading Inside
  APPENDIX-TEXT 中文
]
