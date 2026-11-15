// Labels on questions and subquestions, referenced with @ (local fork).
#import "/lib.typ": *
#show: quiz.with(id: "refs", sets: ("A", "B"))
= Long Questions
+ Demand is $Q = 100 - P$. <demand>

  + #m(1) Find the price. <price>
    #answer(1cm)[$P = 50$; used again in @cs.]
  + #m(2) Using @price, compute consumer surplus. <cs>
    #answer(1cm)[$1250$.]
+ #m(2) Use your answers to @price and @demand.
  #answer(1cm)[See @cs.]
+ #m(1) A third, unlabelled question.
  #answer(1cm)[x]
