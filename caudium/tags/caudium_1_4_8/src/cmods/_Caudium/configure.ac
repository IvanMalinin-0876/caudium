AC_INIT(caudium.c)
AC_CONFIG_HEADER(caudium_machine.h)

CAUDIUM_MODULE_INIT()


AC_ARG_ENABLE(nbio, [Enable NBIO support (defaults to yes)])
if test "x$enable_nbio" != "xno"; then
  AC_DEFINE(ENABLE_NBIO, 1, [Define to enable NBIO support])
fi
AC_HAVE_HEADERS(sys/mman.h linux/mman.h sys/file.h stdio.h stdlib.h string.h ctype.h unistd.h)
AC_CHECK_HEADERS([sys/mman.h linux/mman.h sys/file.h stdio.h stdlib.h string.h ctype.h unistd.h])
AC_HAVE_FUNCS(mmap munmap free getdate getdate_r setproctitle strpbrk)
AC_FUNC_MALLOC
AC_FUNC_ALLOCA
dnl SCO has strftime() and strptime() in libint.
AC_CHECK_FUNCS(strftime, break, [AC_CHECK_LIB(intl, strftime)])
AC_CHECK_FUNCS(strptime, break, [AC_CHECK_LIB(intl, strptime)])
dnl For *BSD that can get his ip :)
AC_CHECK_HEADERS([sys/types.h sys/socket.h netinet/in.h net/if.h net/if_dl.h arpa/inet.h arpa/inet.h])
AC_CHECK_HEADERS([assert.h ifaddrs.h netdb.h])
AC_HAVE_FUNCS(getifaddrs getnameinfo)

dnl if we have strftime, check whether it supports the %z format
if test "$ac_cv_func_strftime" = "yes"; then
  AC_MSG_CHECKING([whether strftime supports the %z format])
  AC_TRY_RUN([
  #include <time.h>

  int main(void) {
    time_t     tim = time(NULL);
    struct tm *tm = localtime(&time);
    if (tm) {
      char buf[16];
      size_t  siz = strftime(buf, sizeof(buf), "%z", tm);
      if (siz == 5 && strlen(buf) == 5)
        return 0;
      else
        return 1;
    }
    
    return 1;
  }],[
   AC_MSG_RESULT([yes])
   AC_DEFINE(STRFTIME_SUPPORTS_Z,,[Define if strftime(3) supports the %z format])
  ])
fi

AC_HEADER_TIME

AC_HAVE_FUNCS(localtime localtime_r gmtime gmtime_r strdupa strndupa)

dnl Test for snprintf..
AC_HAVE_FUNCS(snprintf,[AC_DEFINE(HAVE_SNPRINTF,,[Define to 1 if you have the snprintf function.])],[
AC_MSG_ERROR([Your system lacks the snprintf function. Please send a bug report with OS/environment details to bugs@caudium.info. Caudium can not be built on your system.])])

dnl For _Caudium.cern_http_date() function
AC_STRUCT_TIMEZONE
AC_CHECK_MEMBER(struct tm.tm_gmtoff, [AC_DEFINE(STRUCT_TM_TM_GMTOFF,,[Define if you have struct tm/tm_gmtoff])],,[
#include <sys/types.h>
#include <$ac_cv_struct_tm>
])
AC_MSG_CHECKING([whether timezone is scalar])
AC_TRY_COMPILE([
#include <sys/types.h>
#include <$ac_cv_struct_tm
   ],
   [timezone = 42L],
   [
       AC_MSG_RESULT(yes)
       AC_DEFINE(HAVE_SCALAR_TIMEZONE,,[Define if your timezone is a scalar number]),
   ],
   [   AC_MSG_RESULT(no)    ])

AH_TOP([
/*
 * Caudium - An extensible World Wide Web server
 * Copyright � 2001 The Caudium Group
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

#ifndef CAUDIUM_MACHINE_H
#define CAUDIUM_MACHINE_H

])

AH_BOTTOM([

#endif /* CAUDIUM_MACHINE_H */
])

AC_CHECK_HEADERS([stdio.h alloca.h])

# reset it just in case
CAUDIUM_CPPFLAGS="$CAUDIUM_CPPFLAGS"
AC_SUBST(CAUDIUM_CPPFLAGS)
export CAUDIUM_CPPFLAGS

AC_OUTPUT(Makefile.pre, [make -f Makefile.pre depend])


dnl ## Local Variables:
dnl ## tab-width: 4
dnl ## End:
	
