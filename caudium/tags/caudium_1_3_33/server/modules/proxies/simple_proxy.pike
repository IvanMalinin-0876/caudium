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
 * $Id$
 */
//! module: Simple HTTP-Proxy
//!  This is a complete rewrite of the proxy module. 
//!  It currently does NOT cache, does not allow for 
//!  external filters, and does not allow for proxy 
//!  redirection.<br />
//!  it can be used either as an HTTP proxy, or with 
//!  the redirect module to transparently 'mount' 
//!  other websites in your tree. <br /> Note that 
//!  this module *REQUIRES* a Pike 7.2 and will not 
//!  works with pike 7.0.
//! inherits: module
//! inherits: caudiumlib
//! inherits: socket
//! type: MODULE_FIRST | MODULE_LOCATION
//! cvs_version: $Id$

constant cvs_version = "$Id$";

#include <module.h>

inherit "module";
inherit "caudiumlib";
inherit "socket";

constant module_type = MODULE_PROXY | MODULE_LOCATION;
constant module_name = "Simple HTTP-Proxy";
constant module_doc = "This is a complete rewrite of the proxy module. "
                      "It currently does NOT cache, does not allow for "
                      "external filters, and does not allow for proxy "
                      "redirection.<br />\n"
                      "it can be used either as an HTTP proxy, or with "
                      "the redirect module to transparently 'mount' "
                      "other websites in your tree.<br />"
		      "Note that this module *REQUIRES* a Pike 7.2 and will "
                      "not works with pike 7.0.";
constant module_unique = 0;
//constant thread_safe = 0;	// Is this module not thread safe ?

array status_requests = ({ });

// #define VPROXY_DEBUG

#define WANT_HEADERS /* needs to be defined to get returned error code */

#if __VERSION__ < 7.2
#ifdef VPROXY_DEBUG
void VDEBUG (string x, mixed ... args)
{
   report_error ("VPROXY: " + x + "\n", @args);
}
#else
void VDEBUG (mixed ... args)
{
}
#endif
#else
#ifdef VPROXY_DEBUG
#define VDEBUG(X, args...) report_error ("VPROXY: " + X + "\n", ## args)
#else
#define VDEBUG(X, args...)
#endif 
#endif

void create ()
{
   set_module_creator ("eric lindvall <eric@5stops.com>");

   defvar ("mountpoint", "http:/", "Location", TYPE_LOCATION | VAR_MORE,
           "the mountpoint of your proxy on your virtual filesystem.<br><br>"
           "don't forget to set the \"<b>Proxy security</b>\" settings "
           "under <b>Builtin Variables</b>.");
   defvar ("transparent", 0, "Transparent proxy", TYPE_FLAG,
           "Set this to enable transparent proxy support. In this mode, "
           "the module will use the HTTP host header to proxy the remote website"
           " to the client. With the Virtual Host module and several virtual "
           " servers defined, it can also be used as "
           " a reverse proxy for multiple webservers.<br>"
           "Please also note that checking only the host header for transparent "
           "proxy has some security concerns as the proxy choose the destination"
           " based on a DNS resolution.");
}

string info ()
{
   return (module_doc);
}

string comment ()
{
   return (QUERY (mountpoint));
}

string query_location ()
{
   return (QUERY (mountpoint));
}

string status ()
{
   string res = "";

   VDEBUG ("status_requests = %O\n", status_requests);

   foreach (status_requests, object req)
   {
      if (objectp (req))
      {
         res += req->status () + "<br />\n";
      }
   }

   if (res == "")
      res = "<br />no current connections<br />\n";

   return ("<font size=\"1\">" + res + "</font>");
}

mapping find_file (string file, object id)
{
   object r = request (id, this_object ());
   VDEBUG ("find_file on %s", id->raw_url);

   return Caudium.HTTP.pipe_in_progress();
}

class request
{
   object id;
   object parent;
   object con;
   string host;
   int port;
   string host_header;

   string file;
   string userpass;
   object rpipe;
   int original_length;
   string buffer = "";

#ifdef WANT_HEADERS
   int found_server_headers = 0;
   string server_headers = "";
   int returned_error_code = 0;
#endif

   int bytesent = 0;
   int start_time = time ();

   void create (object _id, object _par)
   {
      id = _id;
      parent = _par;

      parent->status_requests += ({ this_object () });
      VDEBUG ("create::status_requests = %O\n", parent->status_requests);

      id->do_not_disconnect = 1;

      parse_url ();

      rpipe = caudium->pipe ();

      connect_to_server ();
   }

   void parse_url ()
   {
      string query = id->raw_url[sizeof (QUERY (mountpoint)) ..];
      if(QUERY(transparent))
        query = id->host + id->raw_url;

      while (query[0] == '/')
         query = query[1..];

      string not_file;

      if (sscanf (query, "%[^/]/%s", not_file, file) != 2)
      {
         not_file = query;
         file = "";
      }

      not_file = _Roxen.http_decode_string (not_file);

      if (sscanf (not_file, "%[^:]:%d", host, port) != 2)
      {
         host = not_file;
         port = 80;
      }

      sscanf (host, "%s@%s", userpass, host);

      if (port != 80)
         host_header = sprintf ("%s:%d", host, port);
      else
         host_header = host;
   }

   void connect_to_server ()
   {
      async_connect (host, port, connected_to_server);
   }

   void connected_to_server (object _con)
   {
      VDEBUG ("connected_to_server ()");

      con = _con;

      if (!id)
      {
         if (con)
         {
            con->set_blocking ();
            con->close ();
            destruct (con);
         }

         return;
      }

      if (!objectp (con))
      {
         VDEBUG ("no con for %s:%d", host, port);
         return_error (503, sprintf ("DNS resolution of %s failed", host));
         return;
      }

      if (!con->query_address ())
      {
         VDEBUG ("connection refused for %s:%d", host, port);
         return_error (503, sprintf ("The connection to %s failed", host_header));
         return;
      }

      con->set_id (0);
      con->set_nonblocking (0, send_request, completed);
      return;
   }

   void return_error (int errno, string error_message)
   {
      id->misc->error_code = errno;
      id->misc->error_message = error_message;

      mapping error = caudium->http_error->process_error (id);

      id->conf->log (([ "error":errno ]), id);

      id->end (sprintf ("%s %d %s\r\n"
                        "Content-type: %s\r\n"
                        "Content-Length: %d\r\n\r\n%s", 
                        id->prot, error->error, id->errors[errno],
                        error->type, error->len, error->data));
      return;
   }

   void send_request ()
   {
      VDEBUG ("send_request ()");

      con->set_write_callback (0);

      string head = replace (id->raw , "\r\n", "\n");

      int s;
      if ((s = search (head, "\n\n")) >= 0)
         head = head[..s];

      array headers = head / "\n" - ({ "" });

      headers = headers[1..];

      headers = filter (headers, filter_host);

      headers += ({ sprintf ("Host: %s", host_header) });
      headers += ({ "Connection: close" });

      head = headers * "\r\n";

      string request = sprintf ("%s /%s %s\r\n"
                                "%s\r\n\r\n%s", id->method, file, id->prot, head, id->data || "");


      VDEBUG ("sending headers:\n%s\n", request);

      con->write (request);

#ifdef WANT_HEADERS
      con->set_nonblocking (got_data, 0, completed);
#else
      nbio (con, id->my_fd, completed);
#endif

#ifdef EXTRA_DEBUG
      VDEBUG ("request: %s--\n", request);

      VDEBUG ("finished with send_request ()");
#endif
   }

#ifdef WANT_HEADERS
   void parse_server_headers ()
   {
      if (found_server_headers != 1)
         return;

      sscanf (server_headers, "%*s %d %*s\n", returned_error_code);
   }
#endif

   int filter_host (string elem)
   {
      if (lower_case (elem)[0..4] == "host:")
         return (0);
      else if (lower_case (elem)[0..10] == "connection:")
         return (0);
      else if (lower_case (elem)[0..10] == "keep-alive:")
         return (0);
      else if (lower_case (elem)[0..16] == "proxy-connection:")
         return (0);
      return (1);
   }

#ifdef WANT_HEADERS
   void got_data (mixed dummy, string s)
   {
      if (strlen (s))
      {
         if (!found_server_headers)
         {
            int i;

            server_headers += s;

            if ((i = search (server_headers, "\r\n\r\n")) != -1)
            {
               found_server_headers = 1;
               server_headers = server_headers[..i - 1];
            } 
            else if ((i = search (server_headers, "\n\n")) != -1)
            {
               found_server_headers = 1;
               server_headers = server_headers[..i - 1];
            }

            if (found_server_headers)
               parse_server_headers ();

            bytesent += strlen (s);
            buffer += s;
            rpipe->write (s);

            if (found_server_headers)
            {
                VDEBUG ("server headers:\n%s\n--\n", server_headers);

                /* paranoia */
                con->set_blocking (); 
                con->set_read_callback (0);
                con->set_write_callback (0);
                con->set_close_callback (0);

                nbio (con, id->my_fd, completed);
            }
         }
         else
         {
            report_error ("VPROXY: shouldn't call got_data () after we have found headers:\n%s\n", 
                          describe_backtrace (backtrace ()));
            completed ();
         }
      }
   }
#endif

   void nbio (object from, object to, function(:void)|void callback)
   {
      VDEBUG ("nbio (%O)", this_object ());
      rpipe->input (from);
      rpipe->set_done_callback (callback);
      rpipe->output (to);
   }

   void completed ()
   {
      VDEBUG ("completed (%O)", this_object ());

      if (con)
      {
         con->set_blocking ();
         con->close ();
         destruct (con);
      }

      if (objectp (rpipe) && functionp (rpipe->bytes_sent))
         bytesent += rpipe->bytes_sent ();

      if (id)
      {
         if (!returned_error_code)
            returned_error_code = 200;

         id->conf->log (([ "error":returned_error_code,
                           "len":bytesent ]), id);

         id->end ();
      }

      if (rpipe)
         destruct (rpipe);

      float timesince = time(start_time);
      if (timesince <= 0.0)
         timesince = 1.0;

      float bps = bytesent / timesince;

      VDEBUG ("sent %s in %.2f seconds - %s/s", Caudium.sizetostring (bytesent), timesince, Caudium.sizetostring ((int)bps));

      VDEBUG ("done with connection (%O)", this_object ());

      parent->status_requests -= ({ this_object () });
      VDEBUG ("completed::status_requests = %O\n", parent->status_requests);

      destroy ();
   }

   string status ()
   {
      string ret = "";

      int bytes = bytesent;

      if (objectp (rpipe) && functionp (rpipe->bytes_sent))
         bytes  += rpipe->bytes_sent ();

      float timesince = time (start_time);
      if (timesince <= 0.0)
         timesince = 1.0;

      float bps = bytes / timesince;

      ret = sprintf ("%s -&gt; %s sent %s at %s/s", host_header, id->remoteaddr, Caudium.sizetostring (bytes), Caudium.sizetostring ((int) bps));

      return (ret);
   }

   void destroy ()
   {
      parent->status_requests -= ({ this_object () });
      VDEBUG ("destroy::status_requests = %O\n", parent->status_requests);
      VDEBUG ("destroy (%O)", this_object ());
   }

   string _sprintf ()
   {
     return (sprintf ("simple_proxy::request (http://%s/%s)", host_header||"<UNKNOWN>", file||""));
   }
};

/* START AUTOGENERATED DEFVAR DOCS */

//! defvar: mountpoint
//! the mountpoint of your proxy on your virtual filesystem.<br /><br />don't forget to set the "<b>Proxy security</b>" settings under <b>Builtin Variables</b>.
//!  type: TYPE_LOCATION|VAR_MORE
//!  name: Location
//
//! defvar: transparent
//! Set this to enable transparent proxy support. In this mode, the module will use the HTTP host header to proxy the remote website to the client. With the Virtual Host module and several virtual  servers defined, it can also be used as  a reverse proxy for multiple webservers.<br />Please also note that checking only the host header for transparent proxy has some security concerns as the proxy choose the destination based on a DNS resolution.
//!  type: TYPE_FLAG
//!  name: Transparent proxy
//

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

