(library (test utils)
  (export add1 iota)
  (import (rnrs (6)))

  (define (add1 x)
    (+ x 1))

  (define (iota n)
    (define (recur x)
      (if (< x n)
          (cons x (recur (+ x 1)))
          '()))
    (assert (integer? n))
    (recur 0))
)