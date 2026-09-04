// Member B: public mb_helper() uses a static table
static long long table[3] = { 10, 20, 30 };

long long mb_helper(long long x) {
    if (x < 0 || x > 2) return 0;
    return table[x];
}
