(library (test hamts)
  (export hamts)
  (import (rnrs (6))
          (chez-test suite)
          (chez-test assertions)
          (test utils)
          (pfds hamts))
  
  (define (make-string-hamt)
    (make-hamt string-hash string=?))
  
  (define (compare-string-alist l1 l2)
    (lambda (l1 l2)
      (define (compare x y) (string<? (car x) (car y)))
      (equal? (list-sort compare l1)
              (list-sort compare l2))))
  
  (define (bad-hash x) 0)
  
  (define-test-suite hamts
    "Tests for the Hash Array Mapped Trie implementation")
  
  (define-test-case hamts empty-hamt ()
    (assert-predicate hamt? (make-string-hamt))
    (assert-eqv 0 (hamt-size (make-string-hamt))))
  
  (define-test-case hamts hamt-ref/set ()
    ;; Referencing non-existent key
    (assert-equal #f (hamt-ref (make-string-hamt) "foo" #f))
    ;; Referencing a non-existent key (exception)
    (assert-raises assertion-violation? (hamt-ref (make-string-hamt) "bar"))
    ;; Referencing newly-added key
    (assert-equal "bar" (hamt-ref (hamt-set (make-string-hamt) "foo" "bar") "foo" #f))
    (assert-eqv 1 (hamt-size (hamt-set (make-string-hamt) "foo" "bar")))
    ;; shadowing an existing key
    (assert-equal "baz" (hamt-ref (hamt-set (hamt-set (make-string-hamt) "foo" "bar") "foo" "baz") "foo" #f))
    (assert-eqv 1 (hamt-size (hamt-set (hamt-set (make-string-hamt) "foo" "bar") "foo" "baz"))))
  
  (define-test-case hamts hamt-contains ()
    (let ((h (hamt-set (make-string-hamt) "foo" 1)))
      (assert-eqv #t (hamt-contains? h "foo")))
    (let ((h (hamt-set (make-string-hamt) "foo" 1)))
      (assert-eqv #f (hamt-contains? h "bar"))))
  
  (define-test-case hamts hamt-conversion ()
    ;; alist->hamt / distinct keys
    (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l string-hash string=?)))
      (assert-equal (list 1 2 3)
                  (map (lambda (x) (hamt-ref h x #f)) (list "a" "b" "c"))))
    ;; alist->hamt / overlapping keys (leftmost shadows)
    (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3) ("a" . 4)))
           (h (alist->hamt l string-hash string=?)))
      (assert-equal (list 1 2 3)
                  (map (lambda (x) (hamt-ref h x #f)) (list "a" "b" "c"))))
    ;; hamt->alist / distinct keys means left inverse
    (let ((l '(("a" . 1) ("b" . 2) ("c" . 3))))
      (assert-compare compare-string-alist l
                    (hamt->alist (alist->hamt l string-hash string=?)))))
  
  (define-test-case hamts hamt-folding ()
    ;; count size
    (let ((h (alist->hamt '(("a" . 1) ("b" . 2) ("c" . 3)) string-hash string=?))
          (increment (lambda (k v acc) (+ 1 acc))))
      (assert-equal 3 (hamt-fold increment 0 h)))
    ;; copy hamt
    (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l string-hash string=?))
           (add (lambda (k v acc) (hamt-set acc k v))))
      (assert-compare compare-string-alist l
                    (hamt->alist (hamt-fold add (make-string-hamt) h)))))
  
  (define-test-case hamts hamt-removal ()
    ;; removed key exists
    (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l string-hash string=?)))
      (test-case key-exists ()
        (assert-compare compare-string-alist '(("b" . 2) ("c" . 3)) (hamt-delete h "a"))
        (assert-eqv (- (hamt-size h) 1) (hamt-size (hamt-delete h "a")))))
    ;; removed key does not exist
    (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l string-hash string=?)))
      (test-case key-not-exists ()
        (assert-compare compare-string-alist l (hamt-delete h "d"))
        (assert-eqv (hamt-size h) (hamt-size (hamt-delete h "d"))))))
  
  (define-test-case hamts hamt-updates ()
    ;; update non-existent key
    (assert-eqv 1 (hamt-ref (hamt-update (make-string-hamt) "foo" add1 0) "foo" #f))
    ;; update existing key
    (let ((h (hamt-set (make-string-hamt) "foo" 12)))
     (assert-eqv 13 (hamt-ref (hamt-update h "foo" add1 0) "foo" #f))))
  
  (define-test-case hamts hamt-collisions ()
    ;; a bad hash function does not cause problems
    (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l bad-hash string=?)))
      (assert-compare compare-string-alist l (hamt->alist h)))
    ;; stress test, since bigger amounts data usually finds bugs
    (let ((insert (lambda (hamt val) (hamt-set hamt val val)))
          (hash   (lambda (n) (exact (floor (/ n 2))))))
      (assert-eqv 100 (hamt-size (fold-left insert (make-hamt hash =) (iota 100)))))
    ;; collision removal
    (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3) ("d" . 4)))
           (h (alist->hamt l bad-hash string=?)))
      (assert-compare compare-string-alist '()
                    (fold-left (lambda (hamt str) (hamt-delete hamt str))
                           h
                           '("b" "notexists" "d" "a" "c" "notexists"))))
    ;; stress test removal
    (let* ((al (map (lambda (x) (cons x #t)) (iota 100)))
           (hash   (lambda (n) (exact (floor (/ n 2)))))
           (h (alist->hamt al hash =)))
      (assert-eqv 94 (hamt-size (fold-left (lambda (h s) (hamt-delete h s))
                                     h
                                     (list 1 93 72 6 24 48)))))
    ;; collision updates
    (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
           (h (alist->hamt l bad-hash string=?)))
      (assert-compare compare-string-alist
                    '(("a" . 2) ("b" . 3) ("c" . 4))
                    (fold-left (lambda (hamt key)
                             (hamt-update hamt key add1 0))
                           h
                           '("a" "b" "c")))))
  
  (define-test-case hamts hamt-mapping ()
    (let* ((l '(("a" . 97) ("b" . 98) ("c" . 99)))
           (h (alist->hamt l string-hash string=?)))
      (assert-compare compare-string-alist l
                    (hamt->alist (hamt-map (lambda (x) x) h))))
    (let* ((l '(("a" . 97) ("b" . 98) ("c" . 99)))
           (h (alist->hamt l string-hash string=?))
           (stringify (lambda (n) (string (integer->char n)))))
      (assert-compare compare-string-alist
                    '(("a". "a") ("b" . "b") ("c" . "c"))
                    (hamt->alist (hamt-map stringify h))))
    (let ((h (alist->hamt '(("a" . 97) ("b" . 98) ("c" . 99)) string-hash string=?)))
      (assert-eqv (hamt-size h) (hamt-size (hamt-map (lambda (x) x) h)))))
  
)
