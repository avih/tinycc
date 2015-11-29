#ifndef _TCC_GETOPT_H
#define _TCC_GETOPT_H

// musl-libc getopt setup
#include <io.h>

// in musl this code is part of libc, but outside it's better to not prefix '__'
#define __optpos      g__optpos
#define __optreset    g__optreset
#define __getopt_long g__getopt_long

#define optreset      __optreset

#include "tcc/getopt.h"
#include "tcc/getopt.c"
#include "tcc/getopt_long.c"

#endif /* _TCC_GETOPT_H */


/*
Note: The getopt version which is included with tcc for windows comes from musl.
It's POSIX compliant, and doesn't support gnu extensions (most notably: no
optional arguments with '::' and it doesn't permute argv).

If you need gnu getopt, get its files and put them in your project dir, e.g. from:
https://gnunet.org/svn/flightrecorder/src/flightrecorderd/getopt.h
https://gnunet.org/svn/flightrecorder/src/flightrecorderd/getopt.c
https://gnunet.org/svn/flightrecorder/src/flightrecorderd/getopt1.c

Then change '#include <getopt.h>' to '#include "gnu_getopt.h"' in your project,
and create a file "gnu_getopt.h" in your project dir with content below.

Note that while musl's getopt has MIT license, gnu getopt is GPL, so if you use
it, make sure your project complies with its license, since it'll be compiled
directly together with your own code.

//////// Start of gnu_getopt.h ////////
#ifndef _GNU_GETOPT_H
#define _GNU_GETOPT_H

// gnu getopt
// if HAVE_STRING_H then it includes string.h, otherwise strings.h which is bad
#define HAVE_STRING_H 1

#include <stdlib.h>
#include <io.h>

// gnu getopt declares an incorrect prototype of getenv if it's not defined.
// so define it to use a correct getenv
#ifndef getenv
    #define CC_REMOVE_GETENV
    char *fugly_getenv(const char* str) {
        return getenv(str);
    }
    #define getenv fugly_getenv
#endif

#include "getopt.c"
#include "getopt1.c"

#ifdef CC_REMOVE_GETENV
    #undef getenv
#endif

#endif
//////// End of gnu_getopt.h ////////
*/
