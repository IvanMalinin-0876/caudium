/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2000-2002 The Caudium Group
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
 * cache_manager.pike
 *
 * This class maintains the sizes and 
 */


constant cvs_version = "$id: cache_manager.pike,v 1.0 2001/12/26 18:21:00 james_tyson Exp $";

// This object is part of caudium, which handles how much maximum ram and
// disk that the caches can use in total.
// So, if you want to use a cache in a caudium module somewhere you would
// ask for caudium->cache_manager->get_cache( string namespace )
// cache_manager will keep a record of what caches are running and in
// what namespaces they are. It will share out memory between them if the
// total cache ram usage ever grows bigger than the maximum allowable size.
// It's selection algorhythm is pretty simple, it simply calls
// set_maxsize( int n ) on any caches that are bigger than the average
// size of caches with a new memory limit slightly smaller than the one it
// currently has in order to tell the cache to use less RAM. The cache
// object will then set a callout to free() within itself to some time in
// the not too distant future, thus efectively reducing the total ram usage.
// Actually, now that I think of it, why not just lose the per-cache ram
// limit, and have cache_manager call free() in each cache with an amount
// of ram to free, like telling it to lose weight.

	// You should be able to replicate disk_cache.pike to store data
	// in a SQL server or LDAP database, gdmb or what have you.
	// It should even be relatively simple, and eventually will be
	// controlled by a CIF variable.
	// The whole cache is designed to be highly pluggable.
program dcache = (program)"disk_cache";
program rcache = (program)"ram_cache";
program cache = (program)"cache";
program client_cache = (program)"client_cache";
int max_ram_size;
int max_disk_size;
int vigilance;
mapping caches;
mapping client_caches;
string path;
int default_ttl;
int default_halflife;
int _really_started;
object loader;
program pipe = Caudium.nbio;

void create( object _loader ) {
  caches = ([ ]);
  client_caches = ([ ]);
  loader = _loader;
}

void really_start() {
  if ( _really_started ) return;
#ifdef CACHE_DEBUG
  perror( "CACHE: Delayed cache start triggered. Loading caching subsystem: " );
#endif
  loader->caudium->cache_start();
  _really_started = 1;
#ifdef CACHE_DEBUG
  perror( "done.\n" );
#endif
}

string status() {
  if ( ! _really_started ) {
    return "<b>Caching Sub-System Is Currently Innactive.</b>";
  }
  array retval = ({ });
  foreach( sort( indices( caches ) ), string cache ) {
    string ret = "";
    object my = caches[ cache ];
    mapping status = my->status();
    int fast_hitrate = 100;
    int slow_hitrate = 100;
    if ( status->fast_misses ) {
      fast_hitrate = (int)(status->fast_hits / status->fast_misses * 100);
    }
    if ( status->slow_misses ) {
      slow_hitrate = (int)(status->slow_hits / status->slow_misses * 100);
    }
    ret += "<tr><td colspan=4><h1>" + my->namespace + "</h1></td></tr>\n";
    if ( my->cache_description() ) {
      ret += "<tr><td colspan=3>" + my->cache_description() + "</td></tr>\n";
    }
    ret += "<tr><td colspan=4><hr noshade></td></tr>\n";
    ret += "<tr><td colspan=2>Total Hits</td><td colspan=2>" + (string)status->total_hits + "</td></tr>\n";
    ret += "<tr><td colspan=2>Total Misses</td><td colspan=2>" + (string)status->total_misses + "</td></tr>\n";
    ret += "<tr><td colspan=2>Total Object Count</td><td colspan=2>" + (string)status->total_object_count + "</td></tr>\n";
    ret += "<tr><td colspan=4><hr noshade></td></tr>\n";
    ret += "<tr><td colspan=2><b>Fast Cache</b></td><td colspan=2><b>Slow Cache</b></td></tr>\n";
    ret += "<tr><td>Hits</td><td>" + (string)status->fast_hits + "</td><td>Hits</td><td>" + (string)status->slow_hits + "</td></tr>\n";
    ret += "<tr><td>Misses</td><td>" + (string)status->fast_misses + "</td><td>Misses</td><td>" + (string)status->slow_misses + "</td></tr>\n";
    ret += "<tr><td>Objects</td><td>" + (string)status->fast_object_count + "</td><td>Objects</td><td>" + (string)status->slow_object_count + "</td></tr>";
    ret += "<tr><td>Hitrate</td><td>" + (string)fast_hitrate + "%</td><td>Hitrate</td><td>" + (string)slow_hitrate + "%</td></tr>\n";
    retval += ({ ret });
  }
  return "<table border=0>\n" + (retval * "<tr><td colspan=4><br></td></tr>\n") + "</table>\n";
}

private void create_cache( string namespace ) {
  int max_object_ram = (int)(max_ram_size * 0.25);
  int max_object_disk = (int)(max_disk_size * 0.25);
  caches += ([ namespace : cache( namespace, path, max_object_ram, max_object_disk, rcache, dcache, default_ttl ) ]);
}

private int sleepfor() {
	// sleepfor() calculates how long to sleep between callouts to
	// watch_size(), alsolute minimum time for a sleep is 30 seconds,
	// providing that vigilance is set to 100% and the last random
	// call returns 0. Maximum is 21 minutes from the last call
	// (vigilance = 0%)
  return random(1200 * ( 1 - ( vigilance / 100 ) ) ) + 30 + random(30);
}

void start( int _max_ram_size, int _max_disk_size, int _vigilance, string _path, int _default_ttl, int _default_halflife ) {
	// Provide the ability to change the size of the caches on the fly
	// from the config interface.
	// Call set_max_ram_size() and set_max_disk_size() on every cache.
#ifdef CACHE_DEBUG
  roxen_perror( sprintf( "CACHE_MANAGER: start( %d, %d, %d, \"%s\", %d, %d ) called\n", _max_ram_size, _max_disk_size, _vigilance, _path, _default_ttl, _default_halflife ) );
#endif
  max_ram_size = _max_ram_size;
  max_disk_size = _max_disk_size;
  vigilance = _vigilance;
  default_ttl = _default_ttl;
  default_halflife = _default_halflife;
  path = _path;
  foreach( indices( caches ), string namespace ) {
    caches[ namespace ]->set_sizes( max_ram_size * 0.25, max_disk_size * 0.25 );
  }
  call_out( watch_size, sleepfor() );
  call_out( watch_halflife, 3600 );
}

void watch_size() {
  if ( ! _really_started ) {
    call_out( watch_size, sleepfor() );
    return;
  }
#ifdef CACHE_DEBUG
  roxen_perror( "Running watch_size() callout.\n" );
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

void watch_halflife() {
  if ( ! _really_started ) {
    call_out( watch_halflife, 3600 );
    return;
  }
#ifdef CACHE_DEBUG
  roxen_perror( "CACHE: Checking cache halflives.\n" );
#endif
  foreach( indices( caches ), string cache ) {
    if ( caches[ cache ]->last_access < time() - default_halflife ) {
#ifdef CACHE_DEBUG
      roxen_perror( "CACHE: HALFLIFE: Calling stop() on " + cache + "\n" );
#endif
      caches[ cache ]->stop();
    }
  }
  call_out( watch_halflife, 3600 );
}

object get_cache( void|string namespace, void|int client ) {
  really_start();
	// create a cache object using the namespace given and then store
	// it in a mapping and return the object to the caller, thus allowing
	// us to make sure that ram and disk quotas arent exceeded.
        // Also, only call create_cache() if it doesn't already exist - coz
	// if we call create_cache() on a cache that already exists then all
	// it's existing data will effectively be flushed - and possibly
	// corrupted.
  if ( ! namespace ) {
    namespace = "DEFAULT";
  }
  if ( ! caches[ namespace ] ) {
    create_cache( namespace );
  }
  if ( ! client ) {
    if ( client_caches[ namespace ] ) {
      return client_caches[ namespace ];
    }
    else {
      client_caches += ([ namespace : client_cache( caches[ namespace ], get_cache, namespace ) ]);
      return client_caches[ namespace ];
    }
  }
  else {
    return caches[ namespace ];
  }
}

void destroy() {
  stop();
}

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
