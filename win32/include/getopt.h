#ifndef _TCC_GETOPT_H
#define _TCC_GETOPT_H

// musl-libc getopt setup
#include <io.h>

// in musl this code is part of libc, but outside it's better to not prefix '__'
#define __optpos            g__optpos
#define __optreset          g__optreset
#define __getopt_msg        g__getopt_msg
#define __getopt_long       g__getopt_long
#define __getopt_long_core  g__getopt_long_core

#define optreset            __optreset

#include "tcc/getopt.h"
#include "tcc/getopt.c"
#include "tcc/getopt_long.c"

#endif /* _TCC_GETOPT_H */
