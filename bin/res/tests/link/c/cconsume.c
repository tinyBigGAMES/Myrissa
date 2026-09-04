/* C consumer of a Myrissa static library. Proves the archive is consumable
   by a foreign toolchain: symbol names resolve, the calling convention is
   the platform C ABI (win64 / SysV), and the runtime's own imports satisfy
   from the platform link line. */
#include <stdio.h>

int lib_add(int a, int b);
int lib_mul(int a, int b);
int lib_negate(int x);

int main(void)
{
    int r = lib_add(2, 3) * 10 + lib_mul(4, 5) + lib_negate(7);
    printf("cconsume = %d\n", r);          /* 5*10 + 20 - 7 = 63 */
    return r == 63 ? 0 : 1;
}
