@echo off
rem Builds the foreign C archives used by the link compliance suite.
rem Requires zig on PATH or at C:\Dev\Utils\zig\zig.exe.
rem Outputs land in res\tests\link\libtest (all foreign archives).
setlocal
set ZIG=zig
where zig >nul 2>&1 || set ZIG=C:\Dev\Utils\zig\zig.exe
cd /d %~dp0
set OUT=..\libtest
if not exist %OUT% mkdir %OUT%

rem --- win64 (COFF) ---
%ZIG% cc -target x86_64-windows-msvc -c addr64.c  -o addr64.obj  || exit /b 1
%ZIG% cc -target x86_64-windows-msvc -c multi_a.c -o multi_a.obj || exit /b 1
%ZIG% cc -target x86_64-windows-msvc -c multi_b.c -o multi_b.obj || exit /b 1
%ZIG% cc -target x86_64-windows-msvc -c tick.c    -o tick.obj    || exit /b 1
if exist %OUT%\link_addr64.lib del %OUT%\link_addr64.lib
if exist %OUT%\link_multi.lib  del %OUT%\link_multi.lib
if exist %OUT%\tick.lib         del %OUT%\tick.lib
%ZIG% ar rcs %OUT%\link_addr64.lib addr64.obj           || exit /b 1
%ZIG% ar rcs %OUT%\link_multi.lib  multi_a.obj multi_b.obj || exit /b 1
%ZIG% ar rcs %OUT%\tick.lib         tick.obj             || exit /b 1

rem --- win64 (MinGW/GNU COFF) ---
%ZIG% cc -target x86_64-windows-gnu -c gnu_test.c -o gnu_test.obj || exit /b 1
if exist %OUT%\link_gnu_test.lib del %OUT%\link_gnu_test.lib
%ZIG% ar rcs %OUT%\link_gnu_test.lib gnu_test.obj || exit /b 1

rem --- linux64 (ELF) ---
%ZIG% cc -target x86_64-linux-gnu -c addr64.c  -o addr64.o  || exit /b 1
%ZIG% cc -target x86_64-linux-gnu -c multi_a.c -o multi_a.o || exit /b 1
%ZIG% cc -target x86_64-linux-gnu -c multi_b.c -o multi_b.o || exit /b 1
if exist %OUT%\link_addr64.a del %OUT%\link_addr64.a
if exist %OUT%\link_multi.a  del %OUT%\link_multi.a
%ZIG% ar rcs %OUT%\link_addr64.a addr64.o           || exit /b 1
%ZIG% ar rcs %OUT%\link_multi.a  multi_a.o multi_b.o || exit /b 1

del *.obj *.o 2>nul
echo C archives built.
