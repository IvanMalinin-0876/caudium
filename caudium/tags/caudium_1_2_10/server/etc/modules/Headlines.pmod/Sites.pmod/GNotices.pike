/*
 * GNotices backend
 */

import Headlines;

#include <headlines/base.h>
#include <headlines/RDF.h>

constant name = "gnotices";
constant site = "GNotices";
constant url  = "http://news.gnome.org/";
constant path  = "gnome-news/rdf";

constant names = ({ "title", "time" });
constant titles = ({" Application ", " Date " });

constant sub = "Computing/WindowManager";
array headlines;

string entry2txt(mapping hl)
{
  return sprintf("Program: %s\n"
		 "URL:     %s\n"
		 "Date:    %s\n\n",
		 hl->title||"None", HTTPFetcher()->encode(hl->url||""),
		 hl->time);
}

private static void parse_reply(string data)
{
  rdf_parse_reply(data);

  foreach(headlines, mapping hl) {
    array tmp = hl->url / "/";
    hl->time = ctime((int)tmp[-1])[4..23];
  }
}