;; Set up indentation for a couple macros here
((racket-mode .
              ((eval . (put 'All 'racket-indent-function 1))
               (eval . (put 'error-do 'racket-indent-function 1)))))
