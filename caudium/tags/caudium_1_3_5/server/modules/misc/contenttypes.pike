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

//
//! module: Content types
//!  This module handles all normal extension to
//!  content type mapping. Given the file 'foo.html', it will
//!  normally set the content type to 'text/html'
//! inherits: module
//! inherits: caudiumlib
//! type: MODULE_TYPES
//! cvs_version: $Id$
//

/*
 * This module handles all normal extension to content type
 * mapping. Given the file 'foo.html', it will per default
 * set the contenttype to 'text/html'
 */

/*
 * oh joy. no word about module_types in the old roxen docs. i think this leaves pretty much
 * only this file as reference... anyway, so i *think* the api must have been something like that:
 *
 * array(string)type_from_extension(string extension)
 *
 * returns a ({ content-type, content-encoding }) array for a given extension; with content-encoding
 * set to 0 if no such thing belongs to the file (extension?! it doesn't know the filename...)
 *
 * this is unpleasant, and highly unusable. so i'm hereby redefining the api as:
 *
 * array(string)type_from_filename(string filename)
 *
 * returns a ({ content-type, content-encoding }) array for a given filename. content-encoding
 * is set to 0, if no matches found (FIXME: read up on the i<something> stuff).
 * (the old type_from_extension() is left there for backwards compat, but don't use it anymore.
 * if anyone has ever did a MODULE_TYPE, drop me a note. i'd really like to know how/what have
 * you done.
 *
 */

/*
 * mmmmm, a much better parser idea:
 * 0. if(sizeof(line/"/")!=2) { invalid line, discard }
 * 1. foo = (replace(line, ({ "\t" }), ({ " " }))/" ")-({""})
 * 2. if(search(foo, "/")!=-1) { contenttype = foo[0]; exts = foo[1..] }
 * 3. else { exts = foo[0..sizeof(foo)-2] ; contenttype = foo[sizeof(foo)-1] }
 *
 * should be less error-prone, probably simpler to follow... maybe a bit heaver performance-wise, but
 * anyone who has a problem with that may come arguing to me :). oh, don't forget the encodings kludge.
 */


// FIXME: of course module docs don't, as of now, reflect the actual syntax; but it's getting better.

constant cvs_version = "$Id$";
constant thread_safe=1;

#include <module.h>
inherit "module";

constant module_type = MODULE_TYPES;
constant module_name = "Content types";
constant module_doc  = "This module handles all normal extension to "
  "content type mapping. Given the file 'foo.html', it will "
  "normally set the content type to 'text/html'.";
constant module_unique = 1;

// the mappings that hold extension <-> content-type and extension <-> encoding info
mapping (string:string) extensions = ([ ]);
mapping (string:string) encodings = ([ ]);
// stuff to get the accessed statistics
mapping accessed = ([
  "extensions": ([ ]),
  "encodings": ([ ])
]);

// helpers for type_from_filename()
multiset known_exts, known_encs;

void create()
{
  defvar("exts", "\n"
    "# This will include the default extensions from a file.\n"
    "# Feel free to add to this, but do it after the #include line if\n"
    "# you want to override any defaults\n"
    "\n"
    "#include <etc/content-types>\n\n", "Extensions", 
    TYPE_TEXT_FIELD, 
    "This is file extension "
    "to content type mapping. The format is as follows:<br /><br />\n"
    "<i>&lt;extension&gt;&lt;one or more tabs&gt;&lt;content-type&gt;</i><br /><br />\n"
    "<pre>\taif\t\taudio/x-aiff</pre>\n"
    "<pre>\tppm\t\timage/x-portable-pixmap</pre>\n"
    "<pre>\txls\t\tapplication/vnd.ms-excel</pre>\n"
    "<br />"
    "You can use the <b>#include &lt;<i>filename</i>&gt;</b> directive to include "
    "files. The <i>filename</i> argument may be an absolute or a relative path (in the latter case, "
    "it has to be relative to the server's root directory. "
    "For a list of types, see <a href=\"ftp://ftp.isi.edu/in-"
    "notes/iana/assignments/media-types/media-types\">ftp://ftp"
    ".isi.edu/in-notes/iana/assignments/media-types/media-types</a>");
  defvar("extsfile", "/etc/mime.types", "System-wide extension file",
    TYPE_STRING,
    "This is basically the same as the above, but intended for external (to Caudium) "
    "MIME-type databases, like /etc/mime.types on Debian/GNU Linux systems.<br />"
    "The format of this file can be the same as for Extensions, or like this:<br /><br />\n"
    "<i>&lt;content-type&gt;&lt;one or more tabs&gt;&lt;extension&gt;</i><br /><br />\n"
    "<pre>\taudio/x-aiff\taiff</pre>\n"
    "<pre>\timage/x-portable-pixmap\t\tppm</pre>\n"
    "<pre>\tapplication/vnd.ms-excel\txls</pre>\n"
    "Multiple extensions belonging to the same content type may be denoted as a space separated list:<br />\n"
    "<pre>\tapplication/vnd.ms-powerpoint\t\tppt pps pot</pre>\n"
    "<pre>\tapplication/x-httpd-php\t\t\tphtml pht php</pre>\n");
  defvar("default_ct", "application/octet-stream", "Default content type",
    TYPE_STRING, 
    "This is the default content type which is used if a file lacks "
    "extension or if the extension is unknown to the module.<br />"
    "<font color=\"#FF0000\"><b>It is strongly recommended that you do leave this \"application/octet-stream\" at all times.<b></font><br />\n");
  defvar("encs", "\n"
    "# This will include the default enodings from a file.\n"
    "# Feel free to add to this, but do it after the #include line if\n"
    "# you want to override any defaults\n"
    "\n"
    "#include <etc/content-encodings>\n\n", "Encodings",
    TYPE_TEXT_FIELD,
    "This is file extensions to content encodings mapping. These rules tell "
    "Caudium how to set the Content-encoding header for different types of files.\n");
}

string status()
{
  string a, b;
  int even = 0;

  // accessed extensions list follows
  b = "<h2>Accesses per extensions</h2>\n\n";
  b += "<font color = \"#ff0000\">Note: if you are using the \"old\" module api, statistics are not collected.</font><br />\n";
  b += "<table cellpadding=\"4\" cellspacing=\"5\">";
  foreach(sort(indices(accessed["extensions"])), a)
    b += "<tr" + ( (even = !even) ? " bgcolor=\"#d1d1d1\"" : "" ) + "><td>" + a + "</td><td>" + accessed["extensions"][ a ] + "</td></tr>\n";
  b += "</table>\n";

  // accessed encodings list follows
  b += "<h2>Accesses per encodings</h2>\n\n";
  b += "<font color = \"#ff0000\">Note: if you are using the \"old\" module api, statistics are not collected.</font><br />\n";
  b += "<table cellpadding=\"4\" cellspacing=\"5\">";
  a = "";
  even = 0;
  foreach(sort(indices(accessed["encodings"])), a)
    b += "<tr" + ( (even = !even) ? " bgcolor=\"#d1d1d1\"" : "" ) + "><td>" + a + "</td><td>" + accessed["encodings"][ a ] + "</td></tr>\n";
  b += "</table>\n";

  // extension list follows
  b += "<h2>Extensions list</h2>\n\n";
  b += "<table cellpadding=\"4\" cellspacing=\"5\">";
  a = "";
  even = 0;
  foreach(sort(indices(extensions)), a)
    b += "<tr" + ( (even = !even) ? " bgcolor=\"#d1d1d1\"" : "" ) + "><td>" + a + "</td><td>" + extensions[ a ] + "</td></tr>\n";
  b += "</table>\n";

  // encodings list follows
  b += "<h2>Encodings list</h2>\n\n";
  b += "<table cellpadding=\"4\" cellspacing=\"5\">";
  a = "";
  even = 0;
  foreach(sort(indices(encodings)), a)
    b += "<tr" + ( (even = !even) ? " bgcolor=\"#d1d1d1\"" : "" ) + "><td>" + a + "</td><td>" + encodings[ a ] + "</td></tr>\n";
  b += "</table>\n";

  return b;
}

string comment()
{
  return sizeof(extensions) + " extensions, " + sizeof(accessed)+" used.";
}

void parse_ext_string(string exts, mapping m)
{

  /*
   * ok, so the "fuck it all and fucking no regrets" extensions/encodings parser:
   * format is as:
   * extension[" "extension...][\t]+content-type
   * or:
   * content-type[\t]+extension[" "extension...]
   * or:
   * #include <file>
   *
   * the actual case is determined by searching for a forward-slash in the
   * first token.
   *
   * also usable for encodings parsing, as the encodings' format is a subset of the
   * extensions'.
   * leading and trailing whitespaces are removed before any parsing is done!
   *
   * for now, compatibility is kept with the etc/extensions file (ie. STRIP and encodings),
   * but i'm not planning to keep it around for long.
   *
   */

  string line, tmp, lhs, rhs;
  array tmpa;
 
  if( !exts )
    return;

  foreach( exts/"\n", line) {
    line = String.trim_all_whites(lower_case( line ));

    // throw away empty lines
    if( !strlen(line) )
      continue;

    if( line[0] == '#' ) {
      // if the line incidates an #inclusion
      if( sscanf(line, "#include <%s>", string file) ) {
        // then parse it
        if( string s = Stdio.read_bytes(file) )
          parse_ext_string( s, m );
      } else {
      // or throw it away if it's just a comment
        continue;
      }
    }

    
    if(search(line, "\tstrip\t") != -1) {
      // FIXME: this i WANT to get rid of. right now it's here for backwards compat,
      // but i WILL throw that support away.
      perror("contenttypes.pike: STRIP found in a database, engaging horrible kludge\n");
      tmpa = ((line - "strip")/"\t") - ({""});
      encodings[ tmpa[ 0 ] ] = tmpa[ 1 ];
      continue;
    }
    
    tmpa = (line / "\t") - ({""});
    if(sizeof(tmpa) != 2)
      continue;
    lhs = tmpa[ 0 ];
    rhs = tmpa[ 1 ];

    if( search(lhs, "/") != -1) {
      // lhs has "/", so format is "mime-type extension(s)"
      foreach( (rhs/" ")-({""}), tmp)
        m[ tmp ] = lhs;
    } else {
      // lhs has no "/", so format is "extension(s) mime-type"
      foreach( (lhs/" ")-({""}), tmp)
        m[ tmp ] = rhs;
    }

  }

}

void start()
{
  // here we fill up the extensions map from the internal database
  parse_ext_string(QUERY(exts), extensions);
  // if an external one exists, add those too
  if( string s = Stdio.read_bytes(QUERY(extsfile)) )
    parse_ext_string(s, extensions);
  // also for the encodings (internal db only, but can #include others
  parse_ext_string(QUERY(encs), encodings);
  // and our helpers
  known_exts = mkmultiset(indices(extensions));
  known_encs = mkmultiset(indices(encodings));
}

/*
 * the old api fun. left here for posterity and backwards compat.
 */
array type_from_extension(string ext)
{
  ext = lower_case(ext);
  if(ext == "default") {
    return ({ QUERY(default_ct), 0 });
  } else if(extensions[ ext ]) {
    return ({ extensions[ ext ], encodings[ ext ] });
  }
}

/*
 * our shiny new one.
 */
array type_from_filename(string filename) {
  filename = lower_case(filename);
  // set the most sensible default available at this time
  array retval = ({ QUERY(default_ct), 0 });
  array tmp = filename / ".";
  switch(sizeof(tmp)) {
    case 0:
      // strange this would be, we report it, too; then return the default. that should be the most fail-safe to do...
      perror("contenttypes.pike:type_from_filename(): got null filename?\n");
      break;
    case 1:
      // no extensions, return the defaults
      break;
    case 2:
      // one extension: it's either a content-type, or an encoding (calculated in this order)
      // i'm not quite sure whether it's likely to happen or not.
      if( known_exts[ tmp[1] ] ) {
        retval[ 0 ] = extensions[tmp[1]];
        accessed["extensions"][ tmp[1] ]++;
      } else if(known_encs[ tmp[1] ] ) {
        retval[ 1 ] = encodings[ tmp[1] ];
        accessed["encodings"][ tmp[1] ]++;
      };
      break;
    default:
      // two or more extensions. things get two-fold here: either
      // 1. "fil.e.nam.e.extension.encoding", or
      // 2. "file.e.nam.e.extension"

      string _enc = tmp[sizeof(tmp)-1];
      string _ext = tmp[sizeof(tmp)-2];

      if( known_encs[_enc] && known_exts[_ext] ) {
        // here, both encodings and extensions exist, so act accordingly:
        retval[ 0 ] = extensions[_ext];
        retval[ 1 ] = encodings[_enc];
        accessed["extensions"][ _ext ]++;
        accessed["encodings"][ _enc] ++;
      } else if( known_exts[_enc] ) {
      // we're left with the confidence that the last token was not an encoding, so it might be a content-type...
      // no, extensions[_enc] is not a typo. it's just a somewhat badly choosen name.
        retval[ 0 ] = extensions[_enc];
        accessed["extensions"][ _enc ]++;
      };
      // left in the dark. they were neither encodings, nor extensions.
      break;
  }
  return retval;
}


int may_disable() 
{ 
  return 0; 
}

/*
 * If you visit a file that doesn't contain these lines at its end, please
 * cut and paste everything from here to that file.
 */

/*
 * Local Variables:
 * c-basic-offset: 2
 * End:
 *
 * vim: softtabstop=2 tabstop=2 expandtab autoindent formatoptions=croqlt smartindent cindent shiftwidth=2
 */
