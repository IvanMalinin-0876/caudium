/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2000-2003 The Caudium Group
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
 */
/*
 * $Id$
 */

//! $Id$
//! 
//! This file implements SNMP agent for Caudium
//!

constant cvs_version = "$Id$";

//! SNMP Agent
object agent;

//! requests/minute history
object request_history;
int request_last=0;

//! sent/minute history
object sent_history;
int sent_last=0;

//! received/minute history
object received_history;
int received_last=0;

//! Caudium Configuration Object Hook
object caudium;

#include <module.h>

//! Create the SNMP agent
//! @param c
//!    The Caudium Configuration Object.
void create(object c)
{
  mixed err;

  caudium=c;
  if(!GLOBVAR(snmp_address))
  {
    report_error("snmp agent starting on port " + (int)(GLOBVAR(snmp_port)) + "\n");
    err=catch(agent=Protocols.SNMP.agent((int)(GLOBVAR(snmp_port))));
  }
  else // we have specified an address to bind to
  {
    report_error("snmp agent starting on " + GLOBVAR(snmp_address) + 
      " port " + (int)(GLOBVAR(snmp_port)) + "\n");
    err=catch(agent=Protocols.SNMP.agent((int)(GLOBVAR(snmp_port)), GLOBVAR(snmp_address)));
  }
  if(err)
  {
    report_error("Unable to start SNMP agent: " + err[0] + "\n");
    agent=0;
    return;
  }
#ifdef THREADS
  report_error("setting agent to run threaded.\n");
  agent->set_threaded();
#endif
  agent->set_get_communities(({GLOBVAR(snmp_get_community)}));

  // if we allow set access, let it be done here
  if(GLOBVAR(snmp_set_community) && GLOBVAR(snmp_set_community)!="")
    agent->set_set_communities(({GLOBVAR(snmp_set_community)}));

  agent->set_managers_only(0);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.1", snmp_get_server_version);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.2", snmp_get_server_boottime);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.3", snmp_get_server_bootlen);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.4", snmp_get_server_uptime);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.5", snmp_get_server_total_requests);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.6", snmp_get_server_total_received);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.7", snmp_get_server_total_sent);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.8", snmp_get_server_average_requests);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.9", snmp_get_server_average_received);
  agent->set_get_oid_callback("1.3.6.1.4.1.14245.1.100.10", snmp_get_server_average_sent);

  agent->set_set_oid_callback("1.3.6.1.4.1.14245.1.101.1", snmp_set_server_shutdown);
  agent->set_set_oid_callback("1.3.6.1.4.1.14245.1.101.2", snmp_set_server_restart);
  agent->set_set_oid_callback("1.3.6.1.4.1.14245.1.101.3", snmp_set_server_reload_config);

  sent_history=ADT.History(5);
  received_history=ADT.History(5);
  request_history=ADT.History(5);

  call_out(update_counters, 0);
}

//! Send a pre-defined Caudium SNMP trap
//! @param trapname
//!   the name of the trap to send
//! @param trap_recipients
//!   the names of recipients of trap
//! @param trap_community
//!   the community to attach to traps
//! @param args
//!   optional additional arguments
void send_trap(string trapname, array trap_recipients, string trap_community, mixed|void args)
{
  mapping varlist=([]);
  string oid="1.3.6.1.4.1.14245.1";
  int type=6;
  int spectype;

  switch(trapname){
    case "abs_engaged":
      spectype=1;
      break;
    case "server_restart":
      spectype=2;
      break;
    case "server_shutdown":
      spectype=3;
      break;
    case "server_startup":
      spectype=4;
      break;
    case "backtrace":
      spectype=5;
      varlist=(["1.3.6.1.4.1.14245.1.103.1": ({"str", args[0]})]);
      break;
    default:
      spectype=6;
      varlist=(["1.3.6.1.4.1.14245.1.103.2": ({"str", trapname})]);
  }

  foreach(trap_recipients, string recip)
  {
    agent->trap(varlist, oid, type, spectype, 
       ((time()-caudium->start_time)*100), 0, recip);
  }
}

//! Return the server version for SNMP for oid 1.100.1 (under Caudium OID)
array snmp_get_server_version(string oid, mapping rv)
{
  return ({1, "str", caudium->real_version});
}

//! Return the bootime for SNMP for oid 1.100.2 (under Caudium OID)
array snmp_get_server_boottime(string oid, mapping rv)
{
  int boottimeticks;
  boottimeticks=(caudium->boot_time);

  return ({1, "str", ctime(boottimeticks)});
}

//! Return the boot length for SNMP for oid 1.100.3 (under Caudium OID)
array snmp_get_server_bootlen(string oid, mapping rv)
{
  int bootlenticks;
  bootlenticks=(caudium->start_time-caudium->boot_time)*100;

  return ({1, "tick", bootlenticks});
}

//! Return the uptime for SNMP for oid 1.100.4 (under Caudium OID)
array snmp_get_server_uptime(string oid, mapping rv)
{
  int uptimeticks;
  uptimeticks=(time()-caudium->start_time)*100;

  return ({1, "tick", uptimeticks});
}

//! Return the total number of requests for SNMP for oid 1.100.5 (under Caudium OID)
array snmp_get_server_total_requests(string oid, mapping rv)
{
  int requests;

  requests=get_total_requests();

  return ({1, "count64", requests});
}

//! Return the total bytes of data received for SNMP for oid 1.100.6 (under Caudium OID)
array snmp_get_server_total_received(string oid, mapping rv)
{
  int received;
  
  received=get_bytes_received();

  return ({1, "count64", received});
}

//! Return the total bytes of data sent for SNMP for oid 1.100.7 (under Caudium OID)
array snmp_get_server_total_sent(string oid, mapping rv)
{
  int sent;
  
  sent=get_bytes_sent();

  return ({1, "count64", sent});
}

//! Return the 5 minute avg of requests for SNMP for oid 1.100.8 (under Caudium OID)
array snmp_get_server_average_requests(string oid, mapping rv)
{
  int requests;
  requests=ave(request_history);

  return ({1, "count64", requests});
}

//! Return the 5 minute avg of bytes received for SNMP for oid 1.100.9 (under Caudium OID)
array snmp_get_server_average_received(string oid, mapping rv)
{
  int received;
  
  received=ave(received_history);

  return ({1, "count64", received});
}

//! Return the 5 minute avg of bytes sent for SNMP for oid 1.100.10 (under Caudium OID)
array snmp_get_server_average_sent(string oid, mapping rv)
{
  int sent;
  
  sent=ave(sent_history);

  return ({1, "count64", sent});
}

//! Reload all configurations for oid 1.101.3
array snmp_set_server_reload_config(string oid, mixed val, mapping req)
{
  if(val=="1" || val==1)
  {
    call_out(caudium->reload_all_configurations, 5);
    return({1, "str", "Reload configs scheduled"});
  }

  else
  {
    return ({0, Protocols.SNMP.ERROR_BADVALUE});
  }
}

//! Restart the server for oid 1.101.2
array snmp_set_server_restart(string oid, mixed val, mapping req)
{
  if(val=="1" || val==1)
  {
    call_out(caudium->restart, 5);
    return({1, "str", "Restart Scheduled"});
  }

  else
  {
    return ({0, Protocols.SNMP.ERROR_BADVALUE});
  }
}

//! Shutdown the server for oid 1.101.1
array snmp_set_server_shutdown(string oid, mixed val, mapping req)
{
  if(val=="1" || val==1)
  {
    call_out(caudium->shutdown, 5);
    return({1, "str", "Shutdown Scheduled"});
  }

  else
  {
    return ({0, Protocols.SNMP.ERROR_BADVALUE});
  }
}

void destroy()
{
   report_error("Agent shutting down.");
}

//! update rolling request average
int get_total_requests()
{
  int requests;
  foreach(caudium->configurations, object conf) {
#ifdef __AUTO_BIGNUM__
    requests += (conf->requests?conf->requests:0);
#else
    requests += conf->requests?conf->requests:0;
#endif
  }  
  return requests;
}

int get_bytes_received()
{
  int received;
  foreach(caudium->configurations, object conf) {
#ifdef __AUTO_BIGNUM__
    received += (conf->received?conf->received:0);
#else
    received += conf->received?conf->received:0;
#endif
  }  
  return received;
}

int get_bytes_sent()
{
  int sent;
  foreach(caudium->configurations, object conf) {
#ifdef __AUTO_BIGNUM__
    sent += (conf->sent?conf->sent:0);
#else
    sent += conf->sent?conf->sent:0;
#endif
  }  
  return sent;
}

void update_sent_history()
{
  int sent=get_bytes_sent();
  sent_history->push(sent-sent_last);
  sent_last=sent;
}

void update_received_history()
{
  int received=get_bytes_received();
  received_history->push(received-received_last);
  received_last=received;
}

void update_request_history()
{
  int requests=get_total_requests();
  request_history->push(requests-request_last);
  request_last=requests;
}

void update_counters()
{

  update_received_history();
  update_sent_history();
  update_request_history();

  remove_call_out(update_counters);
  call_out(update_counters, 60);
}

mixed ave(object o)
{
   mixed t;

   foreach(values(o), mixed x)
     t+=x;

   t=t/sizeof(o);
   return (int)(t);
}
