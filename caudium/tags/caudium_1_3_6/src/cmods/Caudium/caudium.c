/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2000-2002 The Caudium Group
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

#include "global.h"
RCSID("$Id$");
#include "caudium_util.h"
#include <fd_control.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

#ifdef HAVE_ALLOCA_H
#include <alloca.h>
#endif

#include "caudium.h"

static_strings strs;

/*
**! file: Caudium/caudium.c
**!  Caudium specific classes and functions.
**! cvs_version: $Id$
*/

/*
**! class: Caudium.ParseHTTP
**!  This class is used to parse a HTTP/1.0 or HTTP/1.1 request.
**!  scope: private
*/

static INLINE unsigned char *char_decode_url(unsigned char *str, int len) {
  unsigned char *ptr, *end, *endl2;
  int i, nlen;
  ptr = str;
  end = ptr + len;
  endl2 = end-2; /* to see if there's enough left to make a "hex" char */
  for (nlen = 0, i = 0; ptr < end; i++) {
    switch(*ptr) {
     case '%':
      if (ptr < endl2)
	str[i] = (((ptr[1] < 'A') ? (ptr[1] & 15) :(( ptr[1] + 9) &15)) << 4)|
	  ((ptr[2] < 'A') ? (ptr[2] & 15) : ((ptr[2] + 9)& 15));
      else
	str[i] = '\0';
      ptr+=3;
      nlen++;
      break;
     case '?':
      /* Don't decode more, reached query string*/
      str[i] = '\0';
      return (ptr+1);
      break;
     default:
      str[i] = *(ptr++);
      nlen++;
    }
  }
  str[nlen] = '\0'; /* We will use make_shared_string since a file can't
                       contain \0 anyway. */
  return NULL; /* no query string */
}

/*
**! method: int append(string data)
**!  Append data to the decode buffer.
**! arg: string data
**!  The data to feed to the parser.
**! returns:
**!  1 if decoding is complete (whole header received), 0 if more data is
**!  needed, 413 if the headers are too large or 400 if the request is invalid.
**! name: Caudium.ParseHTTP->append - append data to parse buffer
*/

static void f_buf_append( INT32 args )
{
  struct pike_string *str;
  struct svalue skey, sval; /* header, value */
  int slash_n = 0, cnt, num;
  unsigned char *pp,*ep;
  struct svalue *tmp;
  int os=0, i, j=0, l, qmark = -1;
  unsigned char *in, *query;
  
  if( Pike_sp[-1].type != T_STRING )
    Pike_error("Wrong type of argument to append()\n");
  
  str = Pike_sp[-1].u.string;
  
  if( str->len >= BUF->free ) {
    pop_n_elems(args);
    push_int(413); /* Request Entity Too Large */
    return;
  }

  MEMCPY( BUF->pos, str->str, str->len );

  for( ep = (BUF->pos + str->len), pp = MAX(BUF->data, BUF->pos-3); 
       pp < ep && slash_n < 2; pp++ )
    if( *pp == '\n' )       slash_n++;
    else if( *pp != '\r' )  slash_n=0;
  
  BUF->free -= str->len;
  BUF->pos += str->len;
  BUF->pos[0] = 0;
  pop_n_elems( args );
  if( slash_n != 2 )
  {
    /* need more data */
    push_int( 0 );
    return;
  }

  skey.type = sval.type = T_STRING;

  sval.u.string = make_shared_binary_string( (char *)pp, BUF->pos - pp);
  mapping_insert(BUF->other, SVAL(data), &sval); /* data */
  free_string(sval.u.string);
  
  in = BUF->data;
  l = pp - BUF->data;

  /* find method */
  for( i = 0; i < l; i++ ) {
    if( in[i] == ' ' ) 
      break;
    else if(in[i] == '\n') {
      push_int( 400 ); /* Bad Request */
      return;
    }
  }
  sval.u.string = make_shared_binary_string((char *)in, i);
  mapping_insert(BUF->other, SVAL(method), &sval);
  free_string(sval.u.string);
  
  i++; in += i; l -= i;

  /* find file */
  for( i = 0; i < l; i++ ) {
    if(in[i] == ' ') {
      break;
    } else  if(in[i] == '\n') {
      push_int( 400 ); /* Bad Request */
      return;
    }
  }
  sval.u.string = make_shared_binary_string((char *)in, i);
  mapping_insert(BUF->other, SVAL(raw_url), &sval);
  free_string(sval.u.string);

  /* Decode file part and return pointer to query, if any */
  query = char_decode_url(in, i);

  /* Decoded, query-less file up to the first \0 */
  sval.u.string = make_shared_string((char *)in); 
  mapping_insert(BUF->other, SVAL(file), &sval);
  free_string(sval.u.string);
  
  if(query != NULL)  {
    /* Store the query string */
    sval.u.string = make_shared_binary_string((char *)query, i - (query-in)); /* Also up to first null */
    mapping_insert(BUF->other, SVAL(query), &sval);
    free_string(sval.u.string);
  }
  
  i++; in += i; l -= i;

  /* find protocol */
  for( i = 0; i < l; i++ ) {
    if( in[i] == '\n' ) break;
    else if(in[i] == ' ') {
      push_int( 400 ); /* Bad Request */
      return;
    }
  }
  if( in[i-1] != '\r' ) 
    i++;
  sval.u.string = make_shared_binary_string((char *)in, i-1);
  mapping_insert(BUF->other, SVAL(protocol), &sval);
  free_string(sval.u.string);

  in += i; l -= i;
  if( *in == '\n' ) (in++),(l--);

  for(i = 0; i < l; i++)
  {
    if(in[i] >= 'A' && in[i] <= 'Z') in[i] |= 32; /* Lowercasing the header */
    else if( in[i] == ':' )
    {
      /* in[os..i-1] == the header */
      
      skey.u.string = make_shared_binary_string((char*)in+os, i - os);
      os = i+1;
      while(in[os]==' ') os++; /* Remove initial spaces */
      for(j=os;j<l;j++)  if( in[j] == '\n' || in[j]=='\r')  break; 

      if((tmp = low_mapping_lookup(BUF->headers, &skey)) &&
         tmp->type == T_STRING)
      {
        int len = j - os + 1;
        int len2 = len +tmp->u.string->len;
        sval.u.string = begin_shared_string(len2);
        MEMCPY(sval.u.string->str,
               tmp->u.string->str, tmp->u.string->len);
        sval.u.string->str[tmp->u.string->len] = ',';
        MEMCPY(sval.u.string->str + tmp->u.string->len + 1,
               (char*)in + os, len);
        sval.u.string = end_shared_string(sval.u.string);
      } else {
        sval.u.string = make_shared_binary_string((char*)in + os, j - os);
      }
      
      mapping_insert(BUF->headers, &skey, &sval);
      if( in[j+1] == '\n' ) j++;
      os = j+1;
      i = j;
      free_string(sval.u.string);
      free_string(skey.u.string);
    }
  }
  push_int(1);
}


static void f_buf_create( INT32 args )
{
  if(BUF->data != NULL)
    Pike_error("Create already called!\n");
  switch(args) {
   default:
    Pike_error("Wrong number of arguments to create. Expected 2 or 3.\n");
    break;
	  
   case 3:
    if(Pike_sp[-1].type != T_INT) {
      Pike_error("Wrong argument 3 to create. Expected int.\n");
    } else if(Pike_sp[-1].u.integer < 100) {
      Pike_error("Specified buffer too small.\n");
    } else {
      BUF->free = Pike_sp[-1].u.integer;
    }
    /* fall through */
	  
   case 2:
    if(Pike_sp[-(args - 1)].type != T_MAPPING)
      Pike_error("Wrong argument 2 to create. Expected mapping.\n");	
    if(Pike_sp[-args].type != T_MAPPING)
      Pike_error("Wrong argument 1 to create. Expected mapping.\n");
    break;
  }

  if(BUF->free) {
    BUF->data = (char*)malloc(BUF->free * sizeof(char));
    if(!BUF->data)
      Pike_error("Cannot allocate the request buffer. Out of memory?\n");
  }
  
  BUF->pos = BUF->data;
  add_ref(BUF->headers   = Pike_sp[-(args - 1)].u.mapping);
  add_ref(BUF->other     = Pike_sp[-args].u.mapping);
  pop_n_elems(args);
}

static void free_buf_struct(struct object *o)
{
  if(BUF->headers != NULL ) {
    free_mapping(BUF->headers);
    BUF->headers = NULL;
  }
  if(BUF->other != NULL) {
    free_mapping(BUF->other);
    BUF->other = NULL;
  }
  if(BUF->data) {
    free(BUF->data);
    BUF->data = NULL; /* just in case */
  }
}

static void alloc_buf_struct(struct object *o)
{
  /* This is just the initial buffer of default
   * size. If the size passed to create differs
   * then the buffer will be reallocated.
   */
  BUF->headers = NULL;
  BUF->other = NULL;
  BUF->data = NULL;
  BUF->free = BUFSIZE;
}


/* helper functions */
#ifndef HAVE_ALLOCA
INLINE
#endif
static struct pike_string *lowercase(unsigned char *str, INT32 len)
{
  unsigned char *p, *end;
  unsigned char *mystr;
  struct pike_string *pstr;
#ifdef HAVE_ALLOCA
  mystr = (unsigned char *)alloca((len + 1) * sizeof(char));
#else
  mystr = (unsigned char *)malloc((len + 1) * sizeof(char));
#endif
  if (mystr == NULL)
    return (struct pike_string *)NULL;
  MEMCPY(mystr, str, len);
  end = mystr + len;
  mystr[len] = '\0';
  for(p = mystr; p < end; p++)
  {
    if(*p >= 'A' && *p <= 'Z') {
      *p |= 32; /* OR is faster than addition and we just need
                 * to set one bit :-). */
    }
  }
  pstr = make_shared_binary_string((char *)mystr, len);
#ifndef HAVE_ALLOCA
  free(mystr);
#endif
  return pstr;
}

/* Decode QUERY encoded strings.
   Simple decodes %XX and + in the string. If exist is true, add a null char
   first in the string. 
 */
#ifndef HAVE_ALLOCA
INLINE
#endif
static struct pike_string *url_decode(unsigned char *str, int len, int exist)
{
  int nlen = 0, i;
  unsigned char *mystr; /* Work string */ 
  unsigned char *ptr, *end, *prc; /* beginning and end pointers */
  unsigned char *endl2; /* == end-2 - to speed up a bit */
  struct pike_string *newstr;
#ifdef HAVE_ALLOCA
  mystr = (unsigned char *)alloca((len + 2) * sizeof(char));
#else
  mystr = (unsigned char *)malloc((len + 2) * sizeof(char));
#endif
  if (mystr == NULL)
    return (struct pike_string *)NULL;
  if(exist) {
    ptr = mystr+1;
    *mystr = '\0';
    exist = 1;
  } else
    ptr = mystr;
  MEMCPY(ptr, str, len);
  endl2 = end = ptr + len;
  endl2 -= 2;
  ptr[len] = '\0';

  for (i = exist; ptr < end; i++) {
    switch(*ptr) {
     case '%':
      if (ptr < endl2)
	mystr[i] =
	  (((ptr[1] < 'A') ? (ptr[1] & 15) :(( ptr[1] + 9) &15)) << 4)|
	  ((ptr[2] < 'A') ? (ptr[2] & 15) : ((ptr[2] + 9)& 15));
      else
	mystr[i] = '\0';
      ptr+=3;
      nlen++;
      break;
     case '+':
      ptr++;
      mystr[i] = ' ';
      nlen++;
      break;
     default:
      mystr[i] = *(ptr++);
      nlen++;
    }
  }

  newstr = make_shared_binary_string((char *)mystr, nlen+exist);
#ifndef HAVE_ALLOCA
  free(mystr);
#endif
  return newstr;
}


#if 0
/* Code to add a string to a string */
value = begin_shared_string(count2 - data + exist->u.string->len+1);
MEMCPY(value->str, exist->u.string->str, exist->u.string->len+1);
MEMCPY(value->str + exist->u.string->len + 1,
       heads + data, count2 - data + 1);
value->str[count2 - data + 1 + exist->u.string->len] = '\0';
value = end_shared_string(value);
sval.u.string = value;
mapping_insert(headermap, &skey, &sval);
#endif

INLINE static int get_next_header(unsigned char *heads, int len,
                                  struct mapping *headermap)
{
  int data, count, colon, count2=0;
  struct svalue skey, sval;

  skey.type = T_STRING;
  sval.type = T_STRING;
  
  for(count=0, colon=0; count < len; count++) {
    switch(heads[count]) {
     case ':':
      colon = count;
      data = colon + 1;
      for(count2 = data; count2 < len; count2++)
	/* find end of header data */
	if(heads[count2] == '\r') break;
      while(heads[data] == ' ') data++;
      
      skey.u.string = lowercase(heads, colon);      
      if (skey.u.string == NULL) return -1;
      sval.u.string = make_shared_binary_string((char *)(heads+data),
						count2 - data);
      mapping_insert(headermap, &skey, &sval);
      count = count2;
      free_string(skey.u.string);
      free_string(sval.u.string);
      break;
     case '\n':
      /*printf("Returning %d read\n", count);*/
      return count+1;
    }
  }
  return count;
}

static void f_parse_headers( INT32 args )
{
  struct mapping *headermap;
  struct pike_string *headers;
  unsigned char *ptr;
  int len = 0, parsed = 0;
  get_all_args("Caudium.parse_headers", args, "%S", &headers);
  headermap = allocate_mapping(1);
  ptr = (unsigned char *)headers->str;
  len = headers->len;
  /*
   * FIXME:
   * What do we do if memory allocation fails halfway through
   * allocating a new mapping? Should we return that half-finished
   * mapping or rather return NULL? For now it's the former case.
   * /Grendel
   *
   * If memory allocation fails, just bail out with error()
   */
  while(len > 0 &&
        (parsed = get_next_header(ptr, len, headermap)) >= 0 ) {
    ptr += parsed;
    len -= parsed;
  }
  if(parsed == -1) {
    Pike_error("Caudium.parse_headers(): Out of memory while parsing.\n");
  }
  pop_n_elems(args);
  push_mapping(headermap);
}

/* This function parses the query string */
static void f_parse_query_string( INT32 args )     
{
  struct pike_string *query; /* Query string to parse */
  struct svalue *exist, skey, sval; /* svalues used */
  struct mapping *variables; /* Mapping to store vars in */
  unsigned char *ptr;   /* Pointer to current char in loop */
  unsigned char *name;  /* Pointer to beginning of name */
  unsigned char *equal; /* Pointer to the equal sign */
  unsigned char *end;   /* Pointer to the ending null char */
  int namelen, valulen; /* Length of the current name and value */
  get_all_args("Caudium.parse_query_string", args, "%S%m", &query, &variables);
  skey.type = sval.type = T_STRING;
  /* end of query string */
  end = (unsigned char *)(query->str + query->len);
  name = ptr = (unsigned char *)query->str;
  equal = NULL;
  for(; ptr <= end; ptr++) {
    switch(*ptr)
    {
     case '=':
      /* Allow an unencoded '=' in the value. It's invalid but... */
      if(equal == NULL)
	equal=ptr;
      break;
     case '\0':
      if(ptr != end)
	continue;
     case ';': /* It's recommended to support ';'
		  instead of '&' in query strings... */
     case '&':
      if(equal == NULL) { /* value less variable, we can ignore this */
	name = ptr+1;
	break;
      }
      namelen = equal - name;
      valulen = ptr - ++equal;
      skey.u.string = url_decode(name, namelen, 0);
      if (skey.u.string == NULL) { /* OOM. Bail out */
	Pike_error("Caudium.parse_query_string(): Out of memory in url_decode().\n");
      }
      exist = low_mapping_lookup(variables, &skey);
      if(exist == NULL || exist->type != T_STRING) {
	sval.u.string = url_decode(equal, valulen, 0);
	if (sval.u.string == NULL) { /* OOM. Bail out */
	  Pike_error("Caudium.parse_query_string(): "
		     "Out of memory in url_decode().\n");
	}
      } else {
	/* Add strings separed with '\0'... */
	struct pike_string *tmp;
	tmp = url_decode(equal, valulen, 1);
	if (tmp == NULL) {
	  Pike_error("Caudium.parse_query_string(): "
		     "Out of memory in url_decode().\n");
	}
	sval.u.string = add_shared_strings(exist->u.string, tmp);
	free_string(tmp);
      }
      mapping_insert(variables, &skey, &sval);
      free_string(skey.u.string);
      free_string(sval.u.string);

      /* Reset pointers */
      equal = NULL;
      name = ptr+1;
    }
  }
  pop_n_elems(args);
}

/*
 * Parse the given string and fill the passed multisets with,
 * respectively, "normal" and "internal" prestates. Note that the
 * latter is filled only if the FIRST prestate is "internal" and in
 * such case the former has just one member - "internal".
 * Returns the passed url without the prestate part.
 */
static void f_parse_prestates( INT32 args ) 
{
  struct pike_string    *url;
  struct multiset       *prestate;
  struct multiset       *internal;
  struct svalue          ind;
  char                  *tmp;
  int                    prestate_end = -1;
  int                    done_first = 0, i;
  int                    last_start;
  
  ind.type = T_STRING;
  
  get_all_args("Caudium.parse_prestates", args, "%S%M%M",
               &url, &prestate, &internal);
  if (url->len < 5 || url->str[1] != '(') { /* must have at least '/(#)/ */
    pop_n_elems(args-1);  /* Leave URL on the stack == return it */
    return;
  }
 
  tmp = &url->str[3];
  while (tmp && *tmp) {
    if (*tmp == '/' && *(tmp - 1) == ')') {
      prestate_end = tmp - url->str;
      break;
    }
    tmp++;
  }

  if (prestate_end < 0) {
    pop_n_elems(args-1);  /* Leave URL on the stack == return it */
    return; /* not a prestate */
  }
  
  /*
   * Determine which prestate we should fill.
   */
  last_start = 2;
  for(i = 2; i <= prestate_end; i++) {
    if (url->str[i] == ',' || url->str[i] == ')') {
      int len = i - last_start;
      
      switch(done_first) {
       case 0:
	if (!MEMCMP(&url->str[last_start], "internal", len)) {
	  done_first = -1;
	  ind.u.string = make_shared_string("internal");
	} else {
	  done_first = 1;
	  ind.u.string = make_shared_binary_string(&url->str[last_start], len);
	}
            
	multiset_insert(prestate, &ind);
	break;
            
       case -1:
	/* internal */
	ind.u.string = make_shared_binary_string(&url->str[last_start], len);
	multiset_insert(internal, &ind);
	break;
            
       default:
	/* prestate */
	ind.u.string = make_shared_binary_string(&url->str[last_start], len);
	multiset_insert(prestate, &ind);
	break;
      }
      free_svalue(&ind);
      last_start = i + 1;
    }
  }

  pop_n_elems(args);
  push_string(make_shared_string(url->str + prestate_end));
}

static void f_get_address( INT32 args ) {
  int i;
  struct pike_string *res, *src;
  char *orig;
  if(Pike_sp[-1].type != T_STRING)
    Pike_error("Invalid argument type, expected 8-bit string.\n");
  src = Pike_sp[-1].u.string;
  if(src->len < 7) {
    res = make_shared_binary_string("unknown", 7);
  } else {
    orig = src->str;

    /* We have at most 5 digits for the port (16 bit integer) */
    i = src->len-6;

    /* Unrolled loop to find the space separating the IP address and the port
     * number. We start looking at position 6 from the end and work backwards.
     * This is because we assume there are more 5 digits ports than 4 digit
     * ports etc.
     */
    if(!(orig[i] & 0xDF)) /* char 6 */
      res = make_shared_binary_string(orig, i);
    else if(!(orig[++i] & 0xDF)) /* char 5 */
      res = make_shared_binary_string(orig, i);
    else if(!(orig[++i] & 0xDF)) /* char 4 */
      res = make_shared_binary_string(orig, i);
    else if(!(orig[++i] & 0xDF)) /* char 3 */
      res = make_shared_binary_string(orig, i);
    else if(!(orig[++i] & 0xDF)) /* char 2 */
      res = make_shared_binary_string(orig, i);
    else 
      res = make_shared_binary_string("unknown", 7);
  }
  pop_stack();
  push_string(res);
}


static void f_extension( INT32 args ) {
  int i, found=0;
  struct pike_string *src;
  char *orig, *ptr;

  if(Pike_sp[-1].type != T_STRING)
    SIMPLE_BAD_ARG_ERROR("Caudium.extension", 1, "string");
  src = Pike_sp[-1].u.string;
  if(src->size_shift) {
    Pike_error("Caudium.extension(): Only 8-bit strings allowed.\n");
  }
  orig = src->str;
  for(i = src->len-1; i >= 0; i--) {
    if(orig[i] == 0x2E) {
      found = 1;
      i++;
      break;
    }
  }
  pop_n_elems(args);
  if(found) {
    int len = src->len - i;    
    switch(orig[src->len-1]) {
     case '#': case '~':
      /* Remove unix backup extension */
      len--;
    }
    push_string(make_shared_binary_string(orig+i, len));

  } else {
    push_text("");
  }
}

/* Caudium.create_process */

extern int fd_from_object(struct object *o);

static void internal_add_limit( struct perishables *storage, 
                                char *limit_name,
                                int limit_resource,
                                struct svalue *limit_value )
{
  struct rlimit ol;
  struct plimit *l = NULL;

  if(limit_value->type == T_INT)
  {
    l = malloc(sizeof( struct plimit ));
    l->rlp.rlim_max = limit_value->u.integer;
    l->rlp.rlim_cur = limit_value->u.integer;
  }
 
  if(l)
  {
    l->resource = limit_resource;
    l->next = storage->limits;
    storage->limits = l;
  }
}

static void f_create_process( INT32 args ) {
  struct perishables storage;
  struct array *cmd = 0;
  struct mapping *optional = 0;
  struct svalue *tmp;
  int e;
  int stds[3];
  int *fds;
  int num_fds = 3;
  int wanted_gid=0, wanted_uid=0;
  int gid_request=0, uid_request=0;
  char *tmp_cwd;
  pid_t pid=-2;

  extern char **environ;

  fds = stds;
  storage.env = NULL;
  storage.argv = NULL;
  storage.disabled = 0;
  storage.fds = NULL;
  storage.limits = NULL;

  check_all_args("create_process",args, BIT_ARRAY, BIT_MAPPING | BIT_VOID, 0);

  switch(args)
  {
    default:
      optional=Pike_sp[1-args].u.mapping;
      mapping_fix_type_field(optional);

      if(m_ind_types(optional) & ~BIT_STRING)
        Pike_error("Bad index type in argument 2 to Caudium.create_process()\n");

    case 1: cmd=Pike_sp[-args].u.array;
      if(cmd->size < 1)
        Pike_error("Too few elements in argument array.\n");

      for(e=0; e<cmd->size; e++)
        if(ITEM(cmd)[e].type!=T_STRING)
          Pike_error("Argument is not a string.\n");

      array_fix_type_field(cmd);

      if(cmd->type_field & ~BIT_STRING)
        Pike_error("Bad argument 1 to Caudium.create_process().\n");
  }

  if (optional) {

     if ((tmp = simple_mapping_string_lookup(optional, "gid"))) {
        switch(tmp->type)
	{
	  case T_INT:
	    wanted_gid = tmp->u.integer;
	    gid_request = 1;
	    break;

	  default:
	    Pike_error("Invalid argument for gid.");
	    break;
	}
     } 

     if ((tmp = simple_mapping_string_lookup(optional, "uid"))) {
        switch(tmp->type)
	{
	  case T_INT:
	    wanted_uid = tmp->u.integer;
	    uid_request = 1;
	    break;

	  default:
	    Pike_error("Invalid argument for uid.");
	    break;
	}
     } 

     if((tmp = simple_mapping_string_lookup( optional, "cwd" )) &&
	 tmp->type == T_STRING && !tmp->u.string->size_shift)
       tmp_cwd = tmp->u.string->str;

     if((tmp = simple_mapping_string_lookup( optional, "stdin" )) &&
         tmp->type == T_OBJECT)
     {
        fds[0] = fd_from_object( tmp->u.object );
        if(fds[0] == -1)
          Pike_error("Invalid stdin file\n");
     }

     if((tmp = simple_mapping_string_lookup( optional, "stdout" )) &&
         tmp->type == T_OBJECT)
     {
        fds[1] = fd_from_object( tmp->u.object );
        if(fds[1] == -1)
          Pike_error("Invalid stdout file\n");
     }

     if((tmp = simple_mapping_string_lookup( optional, "stderr" )) &&
         tmp->type == T_OBJECT)
     {
        fds[2] = fd_from_object( tmp->u.object );
        if(fds[2] == -1)
          Pike_error("Invalid stderr file\n");
     }

     if((tmp=simple_mapping_string_lookup(optional, "rlimit"))) {
        struct svalue *tmp2;
        if(tmp->type != T_MAPPING)
          Pike_error("Wrong type of argument for the 'rusage' option. "
		     "Should be mapping.\n");
#define ADD_LIMIT(X,Y,Z) internal_add_limit(&storage,X,Y,Z);
#ifdef RLIMIT_NPROC
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "nproc")))
        ADD_LIMIT( "nproc", RLIMIT_NPROC, tmp2 );
#endif        
#ifdef RLIMIT_MEMLOCK
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "memlock")))
        ADD_LIMIT( "memlock", RLIMIT_MEMLOCK, tmp2 );
#endif        
#ifdef RLIMIT_RSS
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "rss")))
        ADD_LIMIT( "rss", RLIMIT_RSS, tmp2 );
#endif        
#ifdef RLIMIT_CORE
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "core")))
        ADD_LIMIT( "core", RLIMIT_CORE, tmp2 );
#endif        
#ifdef RLIMIT_CPU
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "cpu")))
        ADD_LIMIT( "cpu", RLIMIT_CPU, tmp2 );
#endif        
#ifdef RLIMIT_DATA
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "data")))
        ADD_LIMIT( "data", RLIMIT_DATA, tmp2 );
#endif        
#ifdef RLIMIT_FSIZE
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "fsize")))
        ADD_LIMIT( "fsize", RLIMIT_FSIZE, tmp2 );
#endif        
#ifdef RLIMIT_NOFILE
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "nofile")))
        ADD_LIMIT( "nofile", RLIMIT_NOFILE, tmp2 );
#endif        
#ifdef RLIMIT_STACK
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "stack")))
        ADD_LIMIT( "stack", RLIMIT_STACK, tmp2 );
#endif        
#ifdef RLIMIT_VMEM
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "map_mem"))
         ||(tmp2=simple_mapping_string_lookup(tmp->u.mapping, "vmem")))
        ADD_LIMIT( "map_mem", RLIMIT_VMEM, tmp2 );
#endif        
#ifdef RLIMIT_AS
      if((tmp2=simple_mapping_string_lookup(tmp->u.mapping, "as"))
         ||(tmp2=simple_mapping_string_lookup(tmp->u.mapping, "mem")))
        ADD_LIMIT( "mem", RLIMIT_AS, tmp2 );
#endif
#undef ADD_LIMIT
     }
  }

  if((tmp=simple_mapping_string_lookup(optional, "env"))) {
    if(tmp->type == T_MAPPING) {
      struct mapping *m=tmp->u.mapping;
      struct array *i,*v;
      int ptr=0;
      i=mapping_indices(m);
      v=mapping_values(m);

      storage.env=(char **)xalloc((1+m_sizeof(m)) * sizeof(char *));
      for(e=0;e<i->size;e++)
      {
        if(ITEM(i)[e].type == T_STRING &&
           ITEM(v)[e].type == T_STRING)
        {
          check_stack(3);
          ref_push_string(ITEM(i)[e].u.string);
          push_string(make_shared_string("="));
          ref_push_string(ITEM(v)[e].u.string);
          f_add(3);
          storage.env[ptr++]=Pike_sp[-1].u.string->str;
        }
      }
      storage.env[ptr++]=0;
      free_array(i);
      free_array(v);
    }
  }

  storage.argv = (char **)xalloc((1 + cmd->size) * sizeof(char *));
  for (e = 0; e < cmd->size; e++) storage.argv[e] = ITEM(cmd)[e].u.string->str;
  storage.argv[e] = 0;
  
  th_atfork_prepare();
  
  pid = fork();

  if (pid) {
     th_atfork_parent();
  } else {
     th_atfork_child();
  }

  if (pid == -1) {
     Pike_error("Caudium.create_process() failed.");
  } else if (pid) {
    
    pop_n_elems(args);
    push_int(pid);
    return;

  } else {

    if(storage.limits) {
      struct plimit *l = storage.limits;
      while(l) {
        int tmpres = setrlimit( l->resource, &l->rlp );
        l = l->next;
      }
    }

    if(storage.env) environ = storage.env;

    chdir(tmp_cwd);

    seteuid(0);
    setegid(0);

    setgroups(0, NULL);

    if (gid_request) setgid(wanted_gid);
    if (uid_request) setuid(wanted_uid);
    
    dup2(fds[0], 0);
    dup2(fds[1], 1);
    dup2(fds[2], 2);
	  
    set_close_on_exec(0,0);
    set_close_on_exec(1,0);
    set_close_on_exec(2,0);

    execvp(storage.argv[0],storage.argv);

    exit(99);
  }

  pop_n_elems(args);
  push_int(0);
}

/* Initialize and start module */
void pike_module_init( void )
{
  STRS(data)     = make_shared_string("data");
  STRS(file)     = make_shared_string("file");
  STRS(method)   = make_shared_string("method");
  STRS(protocol) = make_shared_string("protocol");
  STRS(query)    = make_shared_string("query");
  STRS(raw_url)  = make_shared_string("raw_url");

  SVAL(data)->type     = T_STRING;
  SVAL(file)->type     = T_STRING;
  SVAL(method)->type   = T_STRING;
  SVAL(protocol)->type = T_STRING;
  SVAL(query)->type    = T_STRING;
  SVAL(raw_url)->type  = T_STRING;
  
  add_function_constant( "parse_headers", f_parse_headers,
                         "function(string:mapping)", 0);
  add_function_constant( "parse_query_string", f_parse_query_string,
                         "function(string,mapping:void)",
                         OPT_SIDE_EFFECT);
  add_function_constant( "parse_prestates", f_parse_prestates,
                         "function(string,multiset,multiset:string)",
                         OPT_SIDE_EFFECT);
  add_function_constant( "get_address", f_get_address,
                         "function(string:string)", 0);
  add_function_constant( "extension", f_extension,
                         "function(string:string)", 0);
  add_function_constant( "create_process", f_create_process,
                         "function(array(string),void|mapping(string:mixed):int)", 0);

  start_new_program();
  ADD_STORAGE( buffer );
  add_function( "append", f_buf_append,
                "function(string:int)", OPT_SIDE_EFFECT );
  add_function( "create", f_buf_create, "function(mapping,mapping,int|void:void)", 0 );
  set_init_callback(alloc_buf_struct);
  set_exit_callback(free_buf_struct);
  end_class("ParseHTTP", 0);
  init_nbio();
}

/* Restore and exit module */
void pike_module_exit( void )
{
  free_string(STRS(data));
  free_string(STRS(file));
  free_string(STRS(method));
  free_string(STRS(protocol));
  free_string(STRS(query));
  free_string(STRS(raw_url));
  exit_nbio();
}

/*
 * Local Variables:
 * c-basic-offset: 2
 * End:
 */
