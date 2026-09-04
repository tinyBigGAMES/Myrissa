#include <windows.h>  
#pragma comment(lib, "kernel32.lib")  
unsigned long long tick_ms(void) { return GetTickCount64(); }  
