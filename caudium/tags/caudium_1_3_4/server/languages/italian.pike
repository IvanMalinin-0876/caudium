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
 * name = "Italian language plugin ";
 * doc = "Handles the conversion of numbers and dates to Italian. You have to restart the server for updates to take effect. Translation by Francesco Chemolli (kinkie@kame.usr.dsi.unimi.it)";
 */

/*
 *	This code is copyright Francesco Chemolli (kinkie@kame.usr.dsi.unimi.it)
 *	It is free for use in the Roxen WWW server, under the terms of the
 *	GNU General Public License.
 *	Feel free to change it in any way, except removing my name from it.
 *	This code is provided AS IS, without any warranty of any kind, implicit
 *	or explicit.
 *	I didn't get any money for it, making me pay for damage
 *	would be rude, wouldn't it? ^_^
 */

string cvs_version = "$Id$";

string month(int num)
{
  return ({ "Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio",
	    "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre",
	    "Novembre", "Dicembre" })[ num - 1 ];
}

string number (int num)
{
  if (num<0)
    return "meno "+number(-num);
  string tmp;
  switch (num)
    {
    case 0:  return "";
    case 1:  return "uno";
    case 2:  return "due";
    case 3:  return "tre";
    case 4:  return "quattro";
    case 5:  return "cinque";
    case 6:  return "sei";
    case 7:  return "sette";
    case 8:  return "otto";
    case 9:  return "nove";
    case 10: return "dieci";
    case 11: return "undici";
    case 12: return "dodici";
    case 13: return "tredici";
    case 14: return "quattordici";
    case 15: return "quindici";
    case 16: return "sedici";
    case 17: return "diciassette";
    case 18: return "diciotto";
    case 19: return "diciannove";
    case 20: return "venti";
    case 30: return "trenta";
    case 40: return "quaranta";
    case 50: return "cinquanta";
    case 60: return "sessanta";
    case 70: return "settanta";
    case 80: return "ottanta";
    case 90: return "novanta";
    case 100: return "cento";
    case 1000: return "mille";
    case 1000000: return "un milione";

    case 28: case 38: case 48: case 58: case 68: case 78: case 88: case 98:
    case 21: case 31: case 41: case 51: case 61: case 71: case 81: case 91:
      tmp=number(num-(num%10));
      tmp=tmp[..sizeof(tmp)-2]; //need to cut the last char
      return tmp+number(num%10);
    case 22..27: case 29: case 32..37: case 39: case 42..47: case 49: 
    case 52..57: case 59: case 62..67: case 69: case 72..77: case 79: 
    case 82..87: case 89: case 92..97: case 99:
      return number(num-(num%10))+number(num%10);

    case 101..999: 
      if (!(num%100))
	return (number (num/100)+"cento");
      return (number(num-(num%100))+number(num%100));

    case 1001..999999:
      if (!(num%1000))
	return number(num/1000)+"mila";
      return number(num-(num%1000))+number(num%1000);

    case 1000001..999999999:
      if (!(num%1000000))
	return number(num/1000000)+" milioni";
      return number(num-(num%1000000))+" "+number(num%1000000);
    default:
      return "pi� di un miliardo";
    }
  return ("error");
}

string ordered(int i)
{
  return i+"�";
  // I know you prefer to use ISO latin-1, but I just can't type it :P
  // Fixed. BTW, what is the problem typing ^Q282 in emacs? /grubba
	// Maybe I don't use emacs? /kinkie
}

string gendered_num (int num) {
	switch (number(num)[..0]) {
		case "a": case "e": case "i": case "o": case "u":
							return "l'"+num;
		default: return "il "+num;
	}
	return (string)num;
}

string date(int timestamp, mapping|void m)
{
  mapping t1=localtime(timestamp);
  mapping t2=localtime(time(0));

  if(!m) m=([]);

  if(!(m["full"] || m["date"] || m["time"]))
  {
    if(t1["yday"] == t2["yday"] && t1["year"] == t2["year"])
      return "oggi, alle "+ ctime(timestamp)[11..15];
  
    if(t1["yday"]+1 == t2["yday"] && t1["year"] == t2["year"])
      return "ieri, alle "+ ctime(timestamp)[11..15];
  
    if(t1["yday"]-1 == t2["yday"] && t1["year"] == t2["year"])
      return "domani, alle "+ ctime(timestamp)[11..15];
  
    if(t1["year"] != t2["year"])
      return gendered_num(t1["mday"])+ " " +
				month(t1["mon"]+1) + " " + (string)(1900+(int)t1["year"]);
    return gendered_num(t1["mday"])+ " " + month(t1["mon"]+1);
  }

  if (m["full"])
    return "alle "+ ctime(timestamp)[11..15]+", "+
			gendered_num(t1["mday"])+
			" "+month(t1["mon"])+ " "+(string)(1900+(int)t1["year"]);
  if(m["date"])
    return gendered_num(t1["mday"])+
			" "+month(t1["mon"])+" "+(string)(1900+(int)t1["year"]);
  if(m["time"])
    return ctime(timestamp)[11..15];
}

string day(int num)
{
  return ({ "domenica","luned�","marted�","mercoled�",
	    "gioved�","venerd�","sabato" })[ num - 1 ];
}

array aliases()
{
  return ({ "it", "ita", "italiano", "italian" });
}
