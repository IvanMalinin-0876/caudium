/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2000-2004 The Caudium Group
 * Copyright � 1994-2001 Roxen Internet Software
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * The Cache module and the accompanying code is Copyright � 2002 James Tyson.
 * This code is released under the GPL license and is part of the Caudium
 * WebServer.
 *
 * Authors:
 *   James Tyson	<jnt@caudium.net>
 *
 */

//! This module implements multi-namespaced caching of data from within
//! Caudium.

constant cvs_version = "$id: cache_manager.pike,v 1.0 2001/12/26 18:21:00 james_tyson Exp $";

int max_ram_size;
int max_disk_size;
int vigilance;
mapping caches;
mapping client_caches;
int default_ttl;
int default_halflife;
int _really_started;
object caudium;
object slow;

//! Create the datastructures for the cache(s).
void create() {
  caches = ([ ]);
  client_caches = ([ ]);
}

//! Trigger delayed start for the cache, this stops us from having to load
//! up indexes for potentially large caches unless they are actually needed
//! see also: delayed module loading.
static void really_start() {
  if ( _really_started ) return;
#ifdef CACHE_DEBUG
  write( "CACHE: Delayed cache start triggered. Loading caching subsystem: " );
#endif
  caudium->cache_start();
#ifdef CACHE_DEBUG
  write( "done.\n" );
#endif
}

//! returns an HTML string containing status information about the current;y
//! running caches; object count, hitrate, etc.
//!
//! @note
//!   please help me make this not suck. it's way off at the moment.
mapping status() {
  if ( ! _really_started ) {
    return ([]);
  }
  mapping ret = ([]);
  foreach( sort( indices( caches ) ), string cache ) {
    object my = caches[ cache ];
    if (!my) continue;
    ret[cache] = my->status();
  }
  return ret;
}

//! internal method used to create a cache instance.
static void create_cache( string namespace ) {
  int max_object_ram = (int)(max_ram_size * 0.25);
  int max_object_disk = (int)(max_disk_size * 0.25);
  caches += ([ namespace : Cache.Cache( namespace, max_object_ram, max_object_disk, slow->get_storage(namespace), default_ttl ) ]);
}

//! internal method that uses randomness to decide how long to wait in between
//! expiry and size management runs
static int sleepfor() {
	// sleepfor() calculates how long to sleep between callouts to
	// watch_size(), alsolute minimum time for a sleep is 30 seconds,
	// providing that vigilance is set to 100% and the last random
	// call returns 0. Maximum is 21 minutes from the last call
	// (vigilance = 0%)
  return random(1200 * ( 1 - ( vigilance / 100 ) ) ) + 30 + random(30);
}

//! Method called by caudium.pike when a delayed start is neccessary.
//!
//! @param _max_ram_size
//! maximum size of an object that is allowed to be stored in RAM (bytes).
//! 
//! @param _max_disk_size
//! maximum size of an object that is allowed to be stored in slow storage
//! (bytes).
//!
//! @param _vigilance
//! a somewhat magical value that tells the cache how often to check it's size
//! constraints. a value of zero means never, and 100 is every 30 seconds.
//!
//! @param _default_ttl
//! set the default time to live for cache objects that arent stored with a
//! TTL value. (seconds)
//!
//! @param _default_halflife
//! default halflife for caches, ie, after a certain idle time the cache is
//! written out to slow storage and the clones are destructed.
void start( int _max_ram_size, int _max_disk_size, int _vigilance, int _default_ttl, int _default_halflife ) {
	// Provide the ability to change the size of the caches on the fly
	// from the config interface.
	// Call set_max_ram_size() and set_max_disk_size() on every cache.
  _really_started = 1;
#ifdef CACHE_DEBUG
  write( sprintf( "CACHE_MANAGER: start( %d, %d, %d, %d, %d ) called\n", _max_ram_size, _max_disk_size, _vigilance, _default_ttl, _default_halflife ) );
#endif
  max_ram_size = _max_ram_size;
  max_disk_size = _max_disk_size;
  vigilance = _vigilance;
  default_ttl = _default_ttl;
  default_halflife = _default_halflife;
  foreach( indices( caches ), string namespace ) {
    caches[ namespace ]->set_sizes( max_ram_size * 0.25, max_disk_size * 0.25 );
  }
  call_out( watch_size, sleepfor() );
  call_out( watch_halflife, 3600 );
}

//! internal method used to check the size of the caches, and use a fancy
//! mathematical algorhythm (which wont be discussed here) to find the caches
//! with the largest size and force objects to expire until the total size of
//! all caches is back within operational tolerances.
static void watch_size() {
  if ( ! _really_started ) {
    call_out( watch_size, sleepfor() );
    return;
  }
#ifdef CACHE_DEBUG
  write( "Running watch_size() callout.\n" );
#endif
	// sum the total amount of RAM being used by all caches (ram_total), if
	// that is exceeding the maximum amount of ram that we are allowed
	// to use (max_ram_size) then devide the total cache usage by the
	// number of caches that are running (avg_ram_size). Find all caches
	// whose ram_size is greater than avg_ram_size and count them
	// (array big_caches), find the amount of offending ram by subtracting
	// max_ram_size from ram_total (exceed_ram), devide that by the number
	// of big_caches (freethis) and call free( freethis ) on each cache in
	// big_caches. This should be an effective way of managing the amount
	// of ram being used by all the caches without letting a single cache
	// fill it up and not let anything else have any.
	// Once we are sure that everything is finished om the RAM size then
	// repeat the entire process for disk cache.
	// Set another callout to watch_size() using the same randomness rules
	// as decided in create()
  mapping cache_ram_sizes = ([ ]);
  mapping cache_disk_sizes = ([ ]);
  int ram_total, disk_total;
  foreach( indices( caches ), string namespace ) {
    int size = caches[ namespace ]->ram_usage();
    cache_ram_sizes[ namespace ] = size;
    ram_total += size;
  }
  if ( ram_total > max_ram_size ) {
#ifdef CACHE_DEBUG
  write( "CACHE_MANAGER: Caches exceed maximum allowed memory!\n" );
#endif
	// Go into cleanup mode - we have some caches that are using too much ram.
	// Firstly, locate the average cache size.
    int average_size = ram_total / sizeof( indices( caches ) );
	// Next, find out which caches are bigger than the average size.
    array big_caches = ({ });
    foreach( indices( cache_ram_sizes ), string namespace ) {
      if ( cache_ram_sizes[ namespace ] > average_size ) {
        big_caches += ({ namespace });
      }
    }
	// Now figure out how much we need to free in the caches.
    int must_free = ram_total - max_ram_size;
	// Figure out how much to free in each cache.
    int free_each = must_free / sizeof( big_caches );
	// Call free_ram() on each of the cache objects that have too much
	// RAM usage using the value free_each.
    foreach( big_caches, string namespace ) {
      caches[ namespace ]->free_ram( free_each );
    }
  }
	// Thus concludes memory size management.
	// Now we do it all again, but for disk usage.
  foreach( indices( caches ), string namespace ) {
    int size = caches[ namespace ]->disk_usage();
    cache_disk_sizes[ namespace ] = size;
    disk_total += size;
  }
  if ( disk_total > max_disk_size ) {
    int average_size = disk_total / sizeof( indices( caches ) );
    array big_caches = ({ });
    foreach( indices( cache_disk_sizes ), string namespace ) {
      if ( cache_disk_sizes[ namespace ] > average_size ) {
        big_caches += ({ namespace });
      }
    }
    int must_free = max_disk_size - disk_total;
    int free_each = must_free / sizeof( big_caches );
    foreach( big_caches, string namespace ) {
      caches[ namespace ]->free_disk( free_each );
    }
  }
  call_out( watch_size, sleepfor() );
}

//! Check to see whether any caches halflifes have expired - i.e. they havent
//! been used for any operations within a certain period of time.
static void watch_halflife() {
  if ( ! _really_started ) {
    call_out( watch_halflife, 3600 );
    return;
  }
#ifdef CACHE_DEBUG
  write( "CACHE: Checking cache halflives.\n" );
#endif
  foreach( indices( caches ), string cache ) {
    if ( caches[ cache ]->last_access < time() - default_halflife ) {
#ifdef CACHE_DEBUG
      write( "CACHE: HALFLIFE: Calling stop() on " + cache + "\n" );
#endif
      caches[ cache ]->stop();
    }
  }
  call_out( watch_halflife, 3600 );
}

//! public method used to create a new cache instance, or retrieve an instance
//! of an existing one. The trick here is that it's not actually a cache
//! itself, but a wrapper class that allows us to destruct the cache on a
//! halflife expiry, meaning that we dont have any dangling references.
//!
//! @param one
//! if void: this is the DEFAULT namespace, used within the server itself
//! if string: this is a specific namespace that we want a cache for
//! if object: this is a caudium module, interpret the namespace for the
//! cache from the module itself.
object get_cache( void|string|object one ) {
  really_start();
  string namespace;
  if ( stringp( one ) )
    namespace = one;
  else if ( objectp( one ) )
    foreach( caudium->configurations, object conf ) {
      string mname = conf->otomod[ one ];
      if ( mname ) {
        mapping moddata = conf->modules[ mname ];
	if ( moddata )
	  if ( moddata->copies )
	    foreach ( indices( moddata->copies ), int i ) {
	      if ( moddata->copies[ i ] == one )
	        namespace = sprintf( "%s #%d on %s", one->module_name, i, conf->name );
	    }
	  else if ( moddata->master == one || moddata->enabled == one )
	    namespace = sprintf( "%s on %s", one->module_name, conf->name );
      }
    }
  else
    namespace = "DEFAULT";

  if ( client_caches[ namespace ] ) {
    return client_caches[ namespace ];
  }
  else {
    object _cache = low_get_cache(namespace);
    client_caches += ([ namespace : Cache.Client( _cache, low_get_cache, namespace, delete_cache ) ]);
    return client_caches[ namespace ];
  }
}

//! Actually create a real cache instance, or return an existing one.
//!
//! @param namespace
//! The namespace of the cache we want.
static object low_get_cache( string namespace ) {
  if ( ! caches[ namespace ] ) {
    create_cache( namespace );
  }
  return caches[ namespace ];
}

//! Oops! We're being destroyed! Probably Caudium doing something *very* bad,
//! call stop().
void destroy() {
  stop();
}

//! Shutdown a cache or caches.
//! 
//! @param namespace
//! if this parameter exist then try and find a cache by the corresponding name
//! and shut it down. If it's void then shut them all down.
void stop( void|string namespace ) {
  if ( ! _really_started ) return;
  if ( namespace ) {
    if ( caches[ namespace ] ) {
      caches[ namespace ]->stop();
      destruct( caches[ namespace ] );
      m_delete( caches, namespace );
    }
  } else { 
    foreach( indices( caches ), string namespace ) {
      caches[ namespace ]->stop();
      destruct( caches[ namespace ] );
      m_delete( caches, namespace );
    }
  }
}

//! Return a copy of the Argument Cache wrapper class, this is a bit of a kludge.
object get_argcache() {
  return Cache.Argument( this_object() );
}

void set_slowstorage(object _slow) {
  slow = _slow;
}

void delete_cache(string namespace) {
  if (caches[namespace]) {
    caches[namespace]->stop();
    destruct(caches[namespace]);
    m_delete(caches, namespace);
  }
}
