#ifndef I596_TEST_NETBUF_H
#define I596_TEST_NETBUF_H

typedef void *netbuf_t;

extern netbuf_t nb_alloc_wrapper(void *data, unsigned int size,
                                 void freefunc(void *), void *freefunc_arg);

#endif
