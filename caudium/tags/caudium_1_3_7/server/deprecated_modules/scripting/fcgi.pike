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
// This is a roxen module. Copyright � 1996 - 1998, Idonex AB.

//
//! module: Fast-CGI executable support
//!  Partial support for the Fast-CGI interface. This module is useful, but not finished.
//! inherits: modules/scripting/oldcgi
//! type: MODULE_FIRST | MODULE_LOCATION | MODULE_FILE_EXTENSION
//! cvs_version: $Id$
//

// Support for the FastCGI interface, using an external fast-cgi
// wrapper. This should be handled internally.

constant cvs_version = "$Id$";

#include <module.h>
inherit "modules/scripting/oldcgi";

#define ipaddr(x,y) (((x)/" ")[y])

constant module_type = MODULE_FIRST | MODULE_LOCATION | MODULE_FILE_EXTENSION;
constant module_name = "Fast-CGI executable support";
constant module_doc  = "Partial support for the "
      "<a href=http://www.fastcgi.com>Fast-CGI interface</a>. "
      "This module is useful, but not finished.";
constant module_unique = 0;

void create(object c)
{
  ::create(c);

  set("mountpoint", "/fcgi-bin/");

  defvar("numsimul", 1,
	 "Number of simultaneous copies to run", TYPE_INT,
	 "This many copies will be started simultaneousy of each script. "
	 "This is very useful for scripts that take a long time to finish. "
	 "A tip is to use another extension and/or cgi-bin directory for "
	 "these scripts. Remember to code your scripts multi-process safe.");
  
  defvar("ex", 1, "Handle *.fcgi", TYPE_FLAG,
	 "Also handle all '.fcgi' files as Fast-CGI scripts, as well "
	 "as files in the cgi-bin directory. This emulates the behaviour "
	 "of the NCSA server (the extensions to handle can be set in the "
	 "CGI-script extensions variable).");

  set("ext", ({"fcgi"}));
  if (mkdir("/tmp/.Caudium_fcgi_pipes")) {
    chmod("/tmp/.Caudium_fcgi_pipes/.", 01777);
  }
}


string query_name() 
{ 
  return sprintf("Fast-CGI support, mounted on "+query_location());
}

int last;

mapping stof = ([]);


string make_pipe_name(string from)
{
  string s;
  
  if(s = stof[from])
    return s;
  s = "/tmp/.Caudium_fcgi_pipes/"+hash(from);
  while(search(stof,s))
    s+=".2";
  return stof[from] = s;
}

mixed low_find_file(string f, object id, string path)
{
  object pipe1, pipe2;
  string path_info;
  NOCACHE();

  if ((path != "") && (path[-1] == '/')) {
    f = path + f;
  } else {
    f = path + "/" + f;
  }
  
  array st2;
  if(!(st2=file_stat(f)))
    return 0; // File not found.
  if (st2[1]==-2)
    return -1; // It's a directory...

  // Fix PATH_INFO
  if (id->misc->path_info) {
    path_info = id->misc->path_info;
  } else if (f[-1] == '/') {
    // Special case.
    // Most UNIXen ignore the trailing /
    // but we have to make path-info out of it.
    path_info = "/";
    f = f[..sizeof(f)-2];
  }

#ifdef CGI_DEBUG
  roxen_perror("FCGI: Starting '"+f+"'...\n");
#endif
    
  pipe1=Stdio.File();
  pipe2=pipe1->pipe();
    
  array (int) uid;
    
  if(!getuid())
  {
    array us;
    if(QUERY(user)&&id->misc->is_user&&(us = file_stat(id->misc->is_user)))
      uid = us[5..6];
    else if(runuser)
      uid = runuser;
    if(!uid)
      uid = ({ 65534, 65534 });
  }

#ifdef CGI_DEBUG
  roxen_perror("Starting '"+getcwd()+"/bin/fcgi -connect "+make_pipe_name(f)+" "+ f +
	       " "+QUERY(numsimul)+"\n");
#endif
  
  spawne(getcwd()+"/bin/fcgi", ({"-connect", make_pipe_name(f), f,
				 QUERY(numsimul)+"" }),
	 my_build_env_vars(f, id, path_info),
	 pipe1, pipe1, QUERY(stderr)=="browser"?pipe1:Stdio.stderr, dirname(f),
	 uid);

  destruct(pipe1);

  if(id->data)
    pipe2->write(id->data);
  
  return http_stream(pipe2);
}

mixed find_file(string f, object id)
{
  low_find_file(f, id, ::search_path);
}

/* START AUTOGENERATED DEFVAR DOCS */

//! defvar: numsimul
//! This many copies will be started simultaneousy of each script. This is very useful for scripts that take a long time to finish. A tip is to use another extension and/or cgi-bin directory for these scripts. Remember to code your scripts multi-process safe.
//!  type: TYPE_INT
//!  name: Number of simultaneous copies to run
//
//! defvar: ex
//! Also handle all '.fcgi' files as Fast-CGI scripts, as well as files in the cgi-bin directory. This emulates the behaviour of the NCSA server (the extensions to handle can be set in the CGI-script extensions variable).
//!  type: TYPE_FLAG
//!  name: Handle *.fcgi
//