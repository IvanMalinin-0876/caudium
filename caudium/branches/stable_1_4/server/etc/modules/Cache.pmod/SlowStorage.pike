/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2000-2005 The Caudium Group
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

//! This module uses the Caudium Storage API to store data permanently

constant cvs_version = "$Id$";


// we use the expiration check as a base starting point and add a randomization 
// to prevent cache expiration getting stuck in lockstep.
#define EXPIRE_DATA_SYNC 7200 
#define EXPIRE_CHECK 300
#define EXPIRE_RUN_LIMIT 5
inherit "helpers";

string namespace;
int disk_usage;
int _hits, _misses;
object storage;
mapping expiration_data;

int get_expire_check()
{
  return EXPIRE_CHECK + random(EXPIRE_CHECK/10);
}

int get_expire_data_sync()
{
  return EXPIRE_DATA_SYNC + random(EXPIRE_DATA_SYNC/10);
}

//! Initialise the disk cache and create the neccessary data structures.
//!
//! @param namespace
//! The namespace of this cache. Used to keep objects seperate on disk.
//!
//! @param _path
//! The path in the filesystem of the server to store objects under.
void create( string _namespace, object _storage ) {
  storage = _storage;
  namespace = _namespace;
  disk_usage = storage->size();
  call_out( expire_cache, get_expire_check());
  expiration_data = _decode_value(storage->retrieve("/expiration_data"));
  call_out( expire_data_sync, 0);
  if(!expiration_data) expiration_data = ([]);
}

//! Store an object on the disk, and it's metadata in RAM.
//!
//! @param meta
//! The cache mapping from cachelib
void store( mapping meta ) {
  if (!meta)
    return; // yep, that can happen...
  meta->create_time = (meta->create_time?meta->create_time:time());
  meta->last_retrieval = (meta->last_retrieval?meta->last_retrieval:0);
  meta->hits = (meta->hits?meta->hits:0);
  meta->hash = (meta->hash?meta->hash:get_hash( meta->name ));
  switch( meta->type ) {
  case "stdio":
	// I would like to use nbio for this. Caudium.nbio maybe??
    if (!objectp(meta->object) && meta->object->read)
      break;
    string data = meta->object->read();
    meta->object->close();
    meta->size = sizeof( data );
    m_delete( meta, "object" );
    string objpath = Stdio.append_path("/", meta->hash, "/object");
    storage->store(objpath, data);
    string metapath = Stdio.append_path("/", meta->hash, "/meta");
    storage->store(metapath, _encode_value(meta));
    disk_usage += meta->size;
    break;
  case "variable":
    if ( meta->disk_cache ) {
      if ( catch( data = _encode_value( meta->object ) ) )
        break;
      meta->size = sizeof( data );
      m_delete( meta, "object" );
      string objpath = Stdio.append_path("/", meta->hash, "/object");
      storage->store(objpath, data);
      string metapath = Stdio.append_path("/", meta->hash, "/meta");
      storage->store(metapath, _encode_value(meta));
      disk_usage += meta->size;
    }
    break;
  case "image":
    if (meta->disk_cache && objectp(meta->object) && meta->object->xsize && meta->object->ysize) {
      string data = Image.PNM.encode( meta->object );
      meta->size = sizeof( data );
      m_delete( meta, "object" );
      string objpath = Stdio.append_path("/", meta->hash, "/object");
      storage->store(objpath, data);
      string metapath = Stdio.append_path("/", meta->hash, "/meta");
      storage->store(metapath, _encode_value(meta));
      disk_usage += meta->size;
    }
    break;
  default:
#ifdef CACHE_DEBUG
    write( "DISK_CACHE( " + namespace + " ): Unknown object type: " + meta->type + ", discarding.\n" );
#endif
    break;
  }
  
  if(meta->expires)
    expiration_data[meta->hash] = meta->expires;
}

//! Retrieve an object from the disk.
//! Scan the metadata for a mathing object, and then retrieve the object
//! off the disk and return it.
//!
//! @param name
//! The name of the object to be retrieved.
void|mixed retrieve(string name, void|int object_only) {
  string hash = get_hash(name);
  string data = storage->retrieve(Stdio.append_path("/", hash, "/object"));
  mapping meta = _decode_value(storage->retrieve(Stdio.append_path("/", hash, "/meta")));
  if (meta && mappingp(meta)) {
    meta->hits++;
    meta->last_retrieval = time();
    _hits++;
    mapping newmeta = meta;
    if (meta->type == "stdio") {
      meta->object = data;
    }
    else if (meta->type == "variable") {
      meta->object = _decode_value(data);
      if (meta->_program) {
       mixed err = catch((program)meta->object);
       if (err) {
        // This is a test just incase the object has been encoded with a broken codec (eg pike 7.3)
#ifdef CACHE_DEBUG
	 write("Unable to decode program %O!, object = %O, reason = %O", name, meta->object, err);
#endif
         refresh(hash);
         return 0;
        }
      }
      else if (meta->type == "image")
        meta->object = Image.PNM.decode(data);
      if ( ! meta->object ) {
        refresh( name );
	return 0;
      }
      storage->store(Stdio.append_path("/", newmeta->hash, "/meta"), _encode_value(newmeta));
      if (object_only)
        return meta->object;
      return meta;
    }
  }
#ifdef CACHE_DEBUF
  else
    write("Corrupt metadata for %O\n", name);
#endif
  _misses++;
  return 0;
}

//! Remove an object from the disk cache, if it exists.
//!
//! @param name
//! The name of the object to remove.
void refresh(string name) {
  string n = get_hash(name);
  storage->unlink(n);
  m_delete(expiration_data, n);
}

//! Flush the cache.
//!
//! @param regexp
//! A regular expression used to selectively remove matching objects.
void flush( void|string regexp ) {
  if ( regexp ) {
    storage->unlink_regexp(regexp);
    return;
  }
  // flush the cache.
  disk_usage = 0;
  storage->unlink();
  expiration_data = ([]);
  store_expiration();
}

//! Return the amount of disk space being occupied by the cache.
int usage() {
  return disk_usage;
}

//! Write all metadata to the disk so that we can get it all back on restart.
//! Then remove the metadata from RAM and shut down.
void stop() {
#ifdef CACHE_DEBUG
  write("DISK_CACHE: Shutting down (%s)\n", namespace);
#endif
  store_expiration();
  storage->stop();
#ifdef CACHE_DEBUG
  write("DISK_CACHE: All done.\n");
#endif
}

//! Free n bytes of disk space by forcing an expire then removing objects
//! with the lowest hitrate.
void free( int n ) {
  int _usage = disk_usage;
  expire_cache( 1 );
  if ( _usage - disk_usage > n ) {
    return 0;
  }
  int freed;
  array _hash = ({ });
  array _hitrate = ({ });
  foreach(storage->list(), string fname) {
    array tmp = (fname / "/") - ({""});
    if (tmp[1]=="meta")
      continue;
    string hash = tmp[0];
    mapping meta = _decode_value(storage->retrieve(Stdio.append_path("/", hash, "/meta")));
    _hash += ({ hash });
    if (meta)
      _hitrate += ({ (float)meta->hits / (float)( time() - meta->create_time ) });
  }
  sort( _hitrate, _hash );
  foreach( _hash, string hash ) {
    if ( freed >= n ) {
      break;
    }
    mapping meta = _decode_value(storage->retrieve(Stdio.append_path("/", hash, "/meta")));
    if (meta) {
      freed += meta->size;
      disk_usage -= meta->size;
    }
    storage->unlink(Stdio.append_path("/", hash, "/object"));
    storage->unlink(Stdio.append_path("/", hash, "/meta"));
    m_delete(expiration_data, hash);
  }

  store_expiration();
}

//! Remove objects from the cache that have expired.
//!
//! @param nocallout
//! Optionally dont schedule a callout to expire_cache();
void expire_cache( void|int nocallout ) {
#ifdef CACHE_DEBUG
  write( "DISK_CACHE::expire_cache() called.\n" );
#endif

  int starttime = time();

  foreach(expiration_data; string hash; mixed expires) {

    // don't run forever during each expire run
    if((time() - starttime) > EXPIRE_RUN_LIMIT)
    {
      call_out( expire_cache, EXPIRE_RUN_LIMIT );
      break;
    }
    
    if ( expires == -1 ) {
      continue;
    }
    if ( expires <= time() ) {
      mapping meta = _decode_value(storage->retrieve(Stdio.append_path("/", hash, "/meta")));
      disk_usage -= meta->size;

#ifdef CACHE_DEBUG
      write( "Object Expired: %s, expiry: %d, removing from disk.\n", meta->name, meta->expires );
#endif
      storage->unlink(Stdio.append_path("/", hash, "/object"));
      storage->unlink(Stdio.append_path("/", hash, "/meta"));

	  m_delete(expiration_data, hash);
    }
  }

  store_expiration();

  if ( ! nocallout ) {
    call_out( expire_cache, get_expire_check() );
  }
}

void store_expiration()
{
  storage->store("/expiration_data", _encode_value(expiration_data));
}

void expire_data_sync()
{
	array x = indices(expiration_data);
	array y = storage->list();
	array z = allocate(sizeof(y));
	foreach(y; int q; string name)
	{
		string hash;
		hash = (name/"/")[1];
		z[q] = hash;
	}
	
	// remove everything on disc from what we know about
	// leaving all of the records which don't exist on disk.
	x -= z;
	
	// then, we delete those expiration records
	expiration_data -= x;

	
	call_out(expire_data_sync, get_expire_data_sync());
}

//! Return the total number of hits against this cache.
int hits() {
  return _hits;
}

//! Return the total number of misses against this cache.
int misses() {
  return _misses;
}

//! Return the total number of objects in this cache.
int object_count() {
  return sizeof(storage->list()) / 2;
}

//! Private method to encode to bytecode.
//!
//! @param var
//! The pike datatype being encoded.
static string _encode_value( mixed var ) {
  if (programp(var) && master()->Encoder)
    return encode_value( var, master()->Encoder(var) );
  else
    return encode_value( var, master()->Codec() );
}

//! Private method to decode from bytecode.
//!
//! @param data
//! The encoded data.
mixed _decode_value( string data ) {
  mixed obj;
  if (catch(obj =  decode_value( data ))) {
    return 0;
  }
  return obj;
}
