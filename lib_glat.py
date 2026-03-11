"""A few tools for Python development
Boost License, see file ./LICENSE

By Guillaume Lathoud, 2026
glat@glat.info
"""

import datetime, inspect, os, threading, traceback


def get_now_dt():
    return datetime.datetime.now( datetime.timezone.utc )



class LineNo2:
    # inspired from https://stackoverflow.com/questions/56762491/python-equivalent-to-c-line
    def __str__(self):
        return str(inspect.currentframe().f_back.f_back.f_lineno)

get__line2 = LineNo2()


def os_path_basename( s ):  # convenience: the user does not have to `import os`
    return os.path.basename( s )

def sys_stdout_flush():  # convenience: the user does not have to `import sys`
    sys.stdout.flush()

def eH():
    """To just print some verbosity with source filename and lineno:
print(eval(eH()))
"""
    return eC('""')
    
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
a = {"b":123}
eval(pC('">>"+str(a)+"<<"'))
# :__main__:1: ">>"+str(a)+"<<":  >>{'b': 123}<< 
#
# From within a file you'd get a more useful output like:
# :<filename>:<lineno>: ...
"""
    expr_esc = expr.replace( '\\', '\\\\' ).replace( '"', '\\"' )
    return "print("+eC(expr)+")"


def eC(expr):
    """Print a piece of Python code, and its evaluated value, along with
some source filename & line number (to facilitate debugging).

Example usage:

from lib_glat import *
a = {"b":123}
print(eval(eC('">>"+str(a)+"<<"')))
# :__main__:1: ">>"+str(a)+"<<":  >>{'b': 123}<< 
#
# From within a file you'd get a more useful output like:
# :<filename>:<lineno>: ...
"""
    expr_esc = expr.replace( '\\', '\\\\' ).replace( '"', '\\"' )
    return "':'+os_path_basename( (__file__  if  '__file__' in dir()  else  __name__) )+':'+str(get__line2)+\": %(expr_esc)s: \"+ %(expr)s+ '\\n'" % locals()




def synchronized(func):
    """Decorator. Effect: only one thread at a time executes a given
function. Other threads wait. Useful in a multi-thread environment.

Implementation taken from:
https://theorangeduck.com/page/synchronized-python

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

    synced_func.__name__ = f'synced_func( {func.__name__} )'
        
    return synced_func



def tryExceptWrapped( onError ):
    """Decorator to wrap a function `func` with:
`try_except(onError,func,...)`

In case of error, catch most exceptions and errors, extract their
information into a string, and call `onError()` with that string.

Useful when you need to catch and report errors of asynchronous
callbacks (of deferred).


Example usage:

@tryExceptWrapped( onError )
def someAsynchronousCallback(a,b,c):
    assert( a == b, c ) # would call onError() with a string representation of the AssertionError

    """

    def tryExceptWrappedDecorator( func ):

        def wrapped( *args, **kwargs ):
            try_except( onError, func, args, kwargs )

        return wrapped

    return tryExceptWrappedDecorator


def try_except( onError, f, args=(), kwargs={} ):
    """Call `f( *args, **kwargs )`

In case of error, catch most exceptions and errors, extract their
information into a string, and call `onError()` with that string.

Useful when you need to catch and report errors of asynchronous
callbacks (of deferred).

The companion decorator `@tryExceptWrapped( onError )` is probably
more practical in most cases.


Example usage:

try_except( onError, someAsynchronousCallback, a, b, c )

def someAsynchronousCallback(a,b,c):
    assert( a == b, c ) # would call onError() with a string representation of the AssertionError

    """
    try:
        f( *args, **kwargs )
    except Exception as e: # i.e. pretty much any exception, but let
                           # KeybordInterrupt etc. through - see
                           # https://docs.python.org/3.8/library/exceptions.html#exception-hierarchy
        onError(''.join( ['tryExcept( '+f.__name__+' ) caught e:\n']
                         + traceback.format_exception( e )))

