/* Ext2 bit numbering matches NetBSD sys/param.h byte bitmap operations.
 * Callers must bound bit against their bitmap length before using these. */
#ifndef _EXT2_BITMAP_H_
#define _EXT2_BITMAP_H_
#include <sys/types.h>
static __inline__ int
ext2_test_bit(unsigned bit, const u_char *map)
{
    return (map[bit / 8] & (1U << (bit % 8))) != 0;
}
static __inline__ int
ext2_set_bit(unsigned bit, u_char *map)
{
    int old = ext2_test_bit(bit, map);
    map[bit / 8] |= (u_char)(1U << (bit % 8));
    return old;
}
static __inline__ int
ext2_clear_bit(unsigned bit, u_char *map)
{
    int old = ext2_test_bit(bit, map);
    map[bit / 8] &= (u_char)~(1U << (bit % 8));
    return old;
}
#endif
