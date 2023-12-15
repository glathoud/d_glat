module d_glat.core_named_sync;

/*
  Name-based synchronization. Useful e.g. in a multi-thread
  environment to make sure that only one thread accesses a given file
  (name) at any given time.

  guillaume.lathoud@outdooractive.com
  issue#2
 */

private class SimpleLock {}

alias SiloOfName = SimpleLock[string];
alias NuserOfName = uint[string];

private static shared SiloOfName  _silo_of_name;
private static shared NuserOfName _nuser_of_name;

shared static this()
{
  _silo_of_name = typeof( _silo_of_name ).init;
  _nuser_of_name = typeof( _nuser_of_name ).init;
}

private const auto _innerLock = new SimpleLock;

private immutable(SimpleLock) add_user( in string name )
{
  synchronized( _innerLock )
  {
    scope auto _son = cast( SiloOfName* )( &_silo_of_name );
    scope auto _non = cast( NuserOfName* )( &_nuser_of_name );
    
    scope auto _nuser = (*_non)[ name ] = 1 + (*_non).get( name, 0 );
    scope auto p = name in (*_son);
    auto ret = cast( immutable(SimpleLock))
      (p ? *p : ((*_son)[ name ] = new SimpleLock));
    
    return ret;
  }
};
  
private void remove_user( in string name )
{
  synchronized( _innerLock )
  {
    scope auto _son = cast( SiloOfName* )( &_silo_of_name );
    scope auto _non = cast( NuserOfName* )( &_nuser_of_name );
    
    scope auto _nuser = (*_non)[name] = -1 + (*_non)[name];
    if (_nuser == 0)
      {
	(*_non).remove( name );
	(*_son).remove( name );
      }
  }
};

string NAMED_SYNC_DO( in string name, in string what )
/*
  Spend as little time as possible in the a global `synchronized`
  lock to fetch/release the `name`-specific lock. 

  The rest of the time, do `what`, synchronized by the
  `name`-specific lock.

  This way, threads should block each other as little as possible.
*/
{
  return `{
    auto __named_silo__ = add_user( ` ~ name ~ ` );
    scope (exit) { remove_user( ` ~ name ~ ` ); }
    synchronized( __named_silo__ )
    {
      ` ~ what ~ `;
	}

  }`;
}
