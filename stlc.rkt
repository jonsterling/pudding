#lang racket

(require syntax/parse (for-syntax syntax/parse))
#;(require macro-debugger/syntax-browser)
(require "infrastructure.rkt")

(require (for-template racket/base racket/match))

(provide stlc
         type? --> Int String
         addition application function-intro hypothesis int-intro
         length-of-string string-intro )

(define-namespace-anchor stlc)

;; These definitions aren't really used for anything. They're here to
;; get a top-level binding for use in syntax objects representing
;; types.
(define-syntax (Int stx) (raise-syntax-error #f "Type used out of context"))
(define-syntax (String stx) (raise-syntax-error #f "Type used out of context"))
(define-syntax (--> stx) (raise-syntax-error #f "Type used out of context"))

(define-match-expander type
  (lambda (stx)
    (syntax-parse stx
      #:literals (-->)
      [(type (--> t1 t2))
       #'(app syntax->list (list _ t1 t2))]
      [(type Int)
       #'(? (lambda (stx) (and (identifier? stx)
                               (free-identifier=? stx #'Int))))]
      [(type String)
       #'(? (lambda (stx) (and (identifier? stx)
                               (free-identifier=? stx #'String))))]))
  (lambda (stx)
    (syntax-parse stx
      #:literals (-->)
      [(type (--> t1 t2))
       #'(syntax (--> t1 t2))]
      [(type Int)
       #'(syntax Int)]
      [(type String)
       #'(syntax String)])))

(define (type? stx)
  (match stx
    [(type (--> t1 t2))
     (and (type? t1)
          (type? t2))]
    [(type Int) #t]
    [(type String) #t]
    [_ #f]))


;;; Structural rules
(define/contract (hypothesis num)
  (-> natural-number/c rule/c)
  (match-lambda
    [(>> hypotheses goal)
     (if (< num (length hypotheses))
         (done-refining (car (list-ref hypotheses num)))
         (raise-refinement-error
          'hypotheses
          (>> hypotheses goal)
          "Hypothesis out of bounds"))]))


;;; Int rules
(define/contract (int-intro x)
  (-> integer? rule/c)
  (match-lambda
    [(>> _ (type Int))
     (done-refining (datum->syntax #'here x))]
    [other (raise-refinement-error 'int-intro other "goal type must be Int")]))

(define/contract (addition arg-count)
  (-> natural-number/c rule/c)
  (lambda (sequent)
    (match sequent
      [(>> hypotheses (type Int))
       (refinement (build-list arg-count
                               (thunk* (>> hypotheses (type Int))))
                   (lambda arguments
                     (datum->syntax #'here (cons #'+ arguments))))]
      [other (raise-refinement-error 'arg-count other "goal type must be Int")])))

(define/contract (length-of-string sequent) rule/c
  (match sequent
    [(>> hypotheses (type Int))
     (refinement (list (>> (sequent-hypotheses sequent) (type String)))
                 (lambda (argument)
                   #`(string-length #,argument)))]
    [other (raise-refinement-error 'length-of-string other "Goal type must be Int")]))

;;; String rules
(define/contract (string-intro str)
  (-> string? rule/c)
  (match-lambda
    [(>> _ (type String))
     (done-refining (datum->syntax #'here str))]
    [other (raise-refinement-error 'string-intro other "Goal type must be String")]))

;;; Function rules
(define/contract (function-intro x)
  (-> symbol? rule/c)
  (match-lambda
    [(>> hyps (type (--> dom cod)))
     (let* ([new-scope (make-syntax-introducer)]
            [annotated-name (new-scope (datum->syntax #f x) 'add)])
       (refinement (list (>> (cons (cons annotated-name
                                         dom)
                                   hyps)
                             cod))
                   (lambda (extract)
                     #`(lambda (#,annotated-name)
                         #,(new-scope extract 'add)))))]
    [other (raise-refinement-error 'function-intro other "Goal must be function type")]))

(define/contract ((application dom) proof-goal)
  (-> syntax? rule/c)
  (unless (type? dom)
    (raise-refinement-error 'application proof-goal (format "Not a type: ~a" dom)))
  (match proof-goal
    [(>> hypotheses goal)
     (refinement
      (list (>> hypotheses #`(--> #,dom #,goal))
            (>> hypotheses dom))
      (lambda (fun arg)
        #`(#,fun #,arg)))]))

;;; Operational semantics
(define (run-program stx [env empty])
  (syntax-parse stx
    #:literals (lambda + string-length)
    [x
     #:when (identifier? #'x)
     (let ([v (assoc #'x env bound-identifier=?)])
       (if v
           (cdr v)
           (error (format "Variable not found: ~a" #'x))))]
    [x
     #:when (number? (syntax-e #'x))
     #'x]
    [x
     #:when (string? (syntax-e #'x))
     #'x]
    [(lambda (x:id) body)
     stx]
    [(string-length arg)
     (datum->syntax #'here (string-length (syntax-e (run-program #'arg env))))]
    [(+ arg ...)
     (apply + (map (compose syntax->datum
                            (lambda (x) (run-program x env)))
                   (syntax-e #'(arg ...))))]
    [(e1 e2)
     (let ([e1-value (run-program #'e1)]
           [e2-value (run-program #'e2)])
       (syntax-parse e1-value
         [(lambda (x:id) body)
          (run-program #'body (cons (cons #'x e2-value) env))]
         [_ (error (format "Not a function: ~a" e1-value))]))]))

