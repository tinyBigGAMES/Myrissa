/* ADDR64 probe: a pointer table in .data forces IMAGE_REL_AMD64_ADDR64
   relocations (absolute 64-bit addresses), the case a .reloc must cover. */
static int one(void)   { return 1; }
static int two(void)   { return 2; }
static int three(void) { return 3; }

static int (*table[3])(void) = { one, two, three };
static int values[3] = { 10, 20, 30 };
static int *pvalues = values;

int addr64_sum(void)
{
    int s = 0;
    for (int i = 0; i < 3; i++)
        s += table[i]() * pvalues[i];
    return s;   /* 1*10 + 2*20 + 3*30 = 140 */
}
