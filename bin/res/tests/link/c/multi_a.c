// Member A: public ma_sum() calls mb_helper() from member B
extern long long mb_helper(long long x);

long long ma_sum(long long a, long long b) {
    return mb_helper(a) + mb_helper(b);
}
