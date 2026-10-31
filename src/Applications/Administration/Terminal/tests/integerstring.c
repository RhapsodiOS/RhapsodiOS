#include "../IntegerString.h"

static int equal(const char *left, const char *right)
{
    while (*left != 0 && *left == *right) {
        ++left;
        ++right;
    }
    return *left == *right;
}

int main(void)
{
    char *text = itoa(0);
    if (!equal(text, "0"))
        return 1;
    if (!equal(itoa(-2147483647 - 1), "-2147483648"))
        return 1;
    if (!equal(itoa(2147483647), "2147483647"))
        return 1;
    return 0;
}
