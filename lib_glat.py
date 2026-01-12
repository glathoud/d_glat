import threading

# A few tools for Python development
# Boost License, see file ./LICENSE
#
# By Guillaume Lathoud, 2026
# glat@glat.info

import inspect, os

class LineNo2:
    # inspired from https://stackoverflow.com/questions/56762491/python-equivalent-to-c-line
    def __str__(self):
        return str(inspect.currentframe().f_back.f_back.f_lineno)

get__line2 = LineNo2()


def os_path_basename( s ):  # convenience: the user does not have to `import os`
    return os.path.basename( s )

def sys_stdout_flush():  # convenience: the user does not have to `import sys`
    sys.stdout.flush()

def pH():
    """To just print some verbosity with source filename and lineno:
eval(pH())
"""
    return pC('""')
    
def pC(expr):
    """Print a piece of Python code, and its evaluated value, along with
some source filename & line number (to facilitate debugging).

Example usage:

from lib_glat import *
a = {b:123}
eval(pC('">>"+str(a)+"<<"'))
    """
    expr_esc = expr.replace( '\\', '\\\\' ).replace( '"', '\\"' )
    return "print(':'+os_path_basename( (__file__  if  '__file__' in dir()  else  __name__) )+':'+str(get__line2)+\": %(expr_esc)s: \", %(expr)s, '\\n')" % locals()


def synchronized(func):
    """https://theorangeduck.com/page/synchronized-python

Example of use:

total = 0
		
@synchronized
def count():
    global total
    curr = total + 1
    time.sleep(0.1)
    total = curr
"""

    func.__lock__ = threading.Lock()
		
    def synced_func(*args, **kws):
        with func.__lock__:
            return func(*args, **kws)

    return synced_func
