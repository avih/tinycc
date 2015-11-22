@echo off
@rem ----------------------------------------------------
@rem batch file to build tcc using mingw gcc
@rem ----------------------------------------------------

@rem optional variables:
@rem   TCCSTATIC - (default not defined) if defined e.g. to 1, will create static tcc and libtcc
@rem   CC - (default 'gcc') - C compiler. setting this to a tcc executable works fine.
@rem   WINTCCFLAGS - compiler flags, defaults to gcc flags, but tcc won't complain.

pushd %~dp0

@set /p VERSION= < ..\VERSION
echo>..\config.h #define TCC_VERSION "%VERSION%"

@if _%1_==_AMD64_ shift /1 && goto x86_64
@if _%1_==_x64_ shift /1 && goto x86_64

@set target=-DTCC_TARGET_PE -DTCC_TARGET_I386
@if not defined WINTCCFLAGS (@set WINTCCFLAGS=-Os -s -fno-strict-aliasing -Wno-incompatible-pointer-types)
@if not defined CC (@set CC=gcc)
@if _%1_==_debug_ set WINTCCFLAGSCC=-g -ggdb
@set CC=%CC% %WINTCCFLAGS%
@set P=32
@goto tools

:x86_64
@set target=-DTCC_TARGET_PE -DTCC_TARGET_X86_64
@rem mingw 64 has an ICE with -Os
@if not defined WINTCCFLAGS (@set WINTCCFLAGS=-O0 -s -fno-strict-aliasing -Wno-incompatible-pointer-types)
@if not defined CC (@set CC=x86_64-w64-mingw32-gcc)
@if _%1_==_debug_ set WINTCCFLAGSCC=-g -ggdb
@set CC=%CC% %WINTCCFLAGS%
@set P=64
@goto tools

:tools
echo will use %CC% %target%
%CC% %target% tools/tiny_impdef.c -o tiny_impdef.exe
%CC% %target% tools/tiny_libmaker.c -o tiny_libmaker.exe

:libtcc
if not exist libtcc mkdir libtcc
copy ..\libtcc.h libtcc\libtcc.h
copy ..\tcclib.h include\tcclib.h
if not defined TCCSTATIC (
  @rem Fine with CC as tcc, but with gcc from MSYS2, the resulting tcc needs libgcc_s_dw2-1.dll - usable in MSYS2
  %CC% %target% -shared -DLIBTCC_AS_DLL -DONE_SOURCE ../libtcc.c -o libtcc.dll -Wl,-out-implib,libtcc/libtcc.a
  tiny_impdef libtcc.dll -o libtcc/libtcc.def
  @if exist libtcc.def del libtcc.def
) else (
  @rem Currently this works only with CC as tcc
  %CC% %target% -c -DONE_SOURCE ../libtcc.c -o libtcc/libtcc.a
  @rem ar rcs libtcc/libtcc.a libtcc/libtcc.o
)

:tcc
%CC% %target% ../tcc.c -o tcc.exe -ltcc -Llibtcc

:copy_std_includes
copy ..\include\*.h include > nul

:libtcc1.a
.\tcc %target% -c ../lib/libtcc1.c
.\tcc %target% -c lib/crt1.c
.\tcc %target% -c lib/wincrt1.c
.\tcc %target% -c lib/dllcrt1.c
.\tcc %target% -c lib/dllmain.c
.\tcc %target% -c lib/chkstk.S
goto lib%P%

:lib32
.\tcc %target% -c ../lib/alloca86.S
.\tcc %target% -c ../lib/alloca86-bt.S
.\tcc %target% -c ../lib/bcheck.c
tiny_libmaker lib/libtcc1.a libtcc1.o alloca86.o alloca86-bt.o crt1.o wincrt1.o dllcrt1.o dllmain.o chkstk.o bcheck.o
@goto the_end

:lib64
.\tcc %target% -c ../lib/alloca86_64.S
tiny_libmaker lib/libtcc1.a libtcc1.o alloca86_64.o crt1.o wincrt1.o dllcrt1.o dllmain.o chkstk.o

:the_end
del *.o

:makedoc
for /f "delims=" %%i in ('where makeinfo') do set minfo=perl "%%~i"
if "%minfo%"=="" goto :skip_makedoc
echo>..\config.texi @set VERSION %VERSION%
if not exist doc md doc
%minfo% --html --no-split -o doc\tcc-doc.html ../tcc-doc.texi
copy tcc-win32.txt doc
copy ..\tests\libtcc_test.c examples
:skip_makedoc
