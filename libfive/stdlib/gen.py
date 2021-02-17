import os
from datetime import datetime

import parse

def arg_type(a):
    return {'libfive_tree':"'*",
            'vec2': 'libfive-vec2_t',
            'vec3': 'libfive-vec3_t',
            'float': 'float'}[a.type]

def arg_call(a):
    if a.type == 'libfive_tree':
        return '(shape->ptr %s)' % a.name
    elif a.type == 'float':
        return a.name
    elif a.type == 'vec2':
        return '(vec2->ffi %s)' % a.name
    elif a.type == 'vec3':
        return '(vec3->ffi %s)' % a.name
    else:
        raise RuntimeError("Unknown type %s" % a.type)

def format_module(lib, m):
    out = '''#|
Guile bindings to the libfive CAD kernel

DO NOT EDIT BY HAND!
This file is automatically generated from libfive/stdlib/stdlib.h

It was last generated on {} by user {}
|#

(define-module (libfive stdlib {}))
(use-modules (system foreign) (libfive lib) (libfive kernel) (libfive vec))

'''.format(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), os.getlogin(), m)

    for f in lib[m].shapes:
        arg_types = " ".join(map(arg_type, f.args))
        arg_names = " ".join([a.name for a in f.args])
        arg_calls = " ".join(map(arg_call, f.args))
        out += '''(define ffi_{name} (pointer->procedure '*
  (dynamic-func "{raw_name}" stdlib)
  (list {arg_types})))
(define-public ({name} {arg_names})
  {doc}
  (ptr->shape (ffi_{name} {arg_calls})))

'''.format(raw_name=f.raw_name or f.name,
       name=f.name.replace('_', '-'),
       doc='" ' + f.docstring.replace('\n', '\n    ') + '"',
       arg_types=arg_types,
       arg_names=arg_names,
       arg_calls=arg_calls)
    return out[:-1]

stdlib = parse.parse_stdlib()
for m in ['csg']:
    with open('../bind/guile/libfive/stdlib/%s.scm' % m, 'w') as f:
        f.write(format_module(stdlib, m))
