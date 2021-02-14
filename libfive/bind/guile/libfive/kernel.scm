#|
Guile bindings to the libfive CAD kernel
Copyright (C) 2021  Matt Keeter

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
|#
(define-module (libfive kernel))

(use-modules (system foreign) (oop goops) (srfi srfi-28))
(use-modules (libfive lib) (libfive vec))

(define-class <shape> (<number>) (ptr #:init-value #f #:init-keyword #:ptr))
(define (shape? t) (is-a? t <shape>))
(define (tree->shape t) (make <shape> #:ptr t))
(define (shape->tree t) (slot-ref t 'ptr))

(define (ensure-shape t)
  (cond ((shape? t) t)
        ((number? t) (number->shape t))
        (else (scm-error 'wrong-type-arg ensure-shape
               "Wrong argument ~A (should be number or shape) " (list t) (list t)))))

(define-macro (overload func sym) `(begin
  (define-method (,func (a <number>) (b <shape>)) (,func (ensure-shape a) b))
  (define-method (,func (a <shape>) (b <number>)) (,func a (ensure-shape b)))
  (define-method (,func (a <shape>) (b <shape>)) (make-shape ,sym a b)))
)

(overload + 'add)
(overload * 'mul)
(overload min 'min)
(overload max 'max)
(overload - 'sub)
(overload / 'div)
(overload atan 'atan2)
(overload modulo 'mod)
(overload nan-fill 'nanfill)

(overload compare 'compare)
(define-method (compare (a <number>) (b <number>))
  (cond ((< a b) -1)
        ((> a b)  1)
        ( else    0)))

(define-method (+ (a <shape>)) a)
(define-method (* (a <shape>)) a)
(define-method (min (a <shape>)) a)
(define-method (max (a <shape>)) a)

(define-method (expt (a <shape>) (b <fraction>))
  (make-shape 'nth-root (make-shape 'pow a (numerator b))
                        (denominator b)))
(define-method (expt (a <shape>) (b <number>))
  (scm-error 'wrong-type-arg 'expt
      "RHS of exponentiation must be rational, not ~A"
      (list b) (list b)))

(define-method (/ (a <shape>)) (make-shape 'recip a))
(define-method (- (a <shape>)) (make-shape 'neg a))
(define-method (sqrt (a <shape>)) (make-shape 'sqrt a))
(define-method (sin (a <shape>)) (make-shape 'sin a))
(define-method (cos (a <shape>)) (make-shape 'cos a))
(define-method (tan (a <shape>)) (make-shape 'tan a))
(define-method (asin (a <shape>)) (make-shape 'asin a))
(define-method (acos (a <shape>)) (make-shape 'acos a))
(define-method (exp (a <shape>)) (make-shape 'exp a))
(define-method (abs (a <shape>)) (make-shape 'abs a))
(define-method (atan (a <shape>)) (make-shape 'atan a))
(define-method (log (a <shape>)) (make-shape 'log a))
(define (square f) (if (shape? f) (make-shape 'square f) (* f f)))

(define-method (nan-fill (a <number>) (b <number>)) (if (nan? a) b a))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-method (shape-eval (a <shape>) (pt <vec3>))
    (_shape-eval-f a (.x pt) (.y pt) (.z pt)))

(define-method (shape-eval (a <shape>) (lower <vec3>) (upper <vec3>))
    (_shape-eval-i a (.x lower) (.x upper)
                     (.y lower) (.y upper)
                     (.z lower) (.z upper)))

(define-method (shape-derivs (a <shape>) (pt <vec3>))
    (_shape-eval-d a (.x pt) (.y pt) (.z pt)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-syntax-rule (lambda-shape vars ...)
  (ensure-shape
    ((lambda vars ...) (make-shape 'var-x)
                       (make-shape 'var-y)
                       (make-shape 'var-z))))

(define-syntax-rule (define-shape (name . vars) body ...)
  (define name (lambda-shape vars body ...)))

(define-syntax remap-shape
  (syntax-rules ()
    ((remap-shape (shape . vars) x y z)
        (remap-shape shape vars x y z))
    ((remap-shape shape (. vars) x y z)
        (shape-remap shape (lambda-shape vars x)
                           (lambda-shape vars y)
                           (lambda-shape vars z)))))

(define-syntax sequence_
  (syntax-rules ()
   ((sequence_ a) a)
   ((sequence_ a (t . args) . rest)
      (sequence_ (t a . args) . rest))
))

(define-syntax-rule (v->list a)
  (call-with-values (lambda () a) (lambda (. args) args)))

(define-syntax vs->list
  (syntax-rules ()
    ((vs->list a) (list (v->list a)))
    ((vs->list a . rest) (cons (v->list a) (vs->list . rest)))))

(define-syntax-rule (values->list . vs)
  (apply append (vs->list . vs)))

(define-syntax-rule (values-from . vs)
  (apply values (values->list . vs)))

(define-syntax-rule (sequence a . args)
  (apply values (map (lambda (q) (sequence_ q . args))
                     (apply append (vs->list a)))))

;; These are "safe" bindings that can be used in the sandbox
(define libfive-bindings '(
    square
    nan-fill
    constant
    compare
    lambda-shape
    define-shape
    remap-shape
    make-var
    shape->string
    shape-eval
    shape-derivs
    sequence
    values-from
    values->list
    libfive-bindings))
(eval (cons 'export libfive-bindings) (interaction-environment))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (ptr->shape p)
  (tree->shape (make-pointer (pointer-address p) libfive-tree-del-ptr)))

(define-public (number->shape f)
  (ptr->shape (libfive-tree-const f)))

(define-public (opcode-enum s)
  (define op (libfive-opcode-enum (string->pointer (symbol->string s))))
  (if (eq? op -1)
    (error (format "Invalid opcode: ~s" s))
    op))

(define-public (var? t)
  (equal? 1 (libfive-tree-is-var (shape->tree t))))
(define-public (make-var)
  (ptr->shape (libfive-tree-var)))

(define* (make-shape op #:optional a b)
  (define opcode (opcode-enum op))
  (define args (libfive-opcode-args opcode))
  (cond
    ((= args 0)
      (if (or a b)
        (error (format "Opcode ~s takes 0 arguments" op))
        (ptr->shape (libfive-tree-nullary opcode))))
    ((= args 1)
      (if (or (not (shape? a)) b)
        (error (format "Opcode ~s takes 1 shape argument" op))
        (ptr->shape (libfive-tree-unary opcode (shape->tree a)))))
    ((= args 2)
      (if (or (not (shape? a)) (not (shape? b)))
        (error (format "Opcode ~s takes 2 shape arguments" op))
        (ptr->shape (libfive-tree-binary opcode (shape->tree a) (shape->tree b)))))
))
(export make-shape)

(define-public (constant t)
  " Returns a new Shape which represents the given shape with its free variables
    locked (so that the partial derivatives with respect to those vars is 0).
    This is useful to fine-tune the behavior of direct modeling."
  (make-shape 'const-var t))

(define-public (shape-tree-id t)
  " Returns an id for the given tree.

    This ID is not globally deduplicated for trees other than x/y/z and free
    variables; in other words (+ x y) and (+ x y) will have different IDs."
  (libfive-tree-id (shape->tree t)))

(define-public (shape-remap t x' y' z')
  " Remaps a shape with the given transform.

  Consider using the remap-shape syntax form instead, for ease of use."
  (ptr->shape (libfive-tree-remap (shape->tree t)
    (shape->tree x') (shape->tree y') (shape->tree z'))))

(define-public (shape->string t)
  (define s (libfive-tree-print (shape->tree t)))
  (define out (pointer->string s))
  (libfive-free s)
  out)

#|
  Low-level functions that need to be ported over
    scm_c_define_gsubr("_shape-eval-f", 4, 0, 0, (void*)scm_shape_eval_f);
    scm_c_define_gsubr("_shape-eval-i", 7, 0, 0, (void*)scm_shape_eval_i);
    scm_c_define_gsubr("_shape-eval-d", 4, 0, 0, (void*)scm_shape_eval_d);
    scm_c_define_gsubr("shape->mesh", 4, 0, 0, (void*)scm_shape_to_mesh);
    scm_c_define_gsubr("shapes->mesh", 6, 0, 0, (void*)scm_shapes_to_mesh);
    scm_c_define_gsubr("shape->string", 1, 0, 0, (void*)scm_shape_to_string);
    scm_c_define_gsubr("save-shape", 2, 0, 0, (void*)scm_shape_save);
    scm_c_define_gsubr("load-shape", 1, 0, 0, (void*)scm_shape_load);
|#

(export shape? <shape> shape-tree-id number->shape
        shape-eval shape->mesh shapes->mesh save-shape load-shape)

#|
  (add-to-load-path (getcwd))
|#
