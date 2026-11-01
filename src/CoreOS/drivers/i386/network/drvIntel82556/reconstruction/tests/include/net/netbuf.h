#ifndef _NETBUF_
#define _NETBUF_

typedef struct { char opaque[1]; } *netbuf_t;

extern netbuf_t nb_alloc_wrapper(void *data, unsigned int size,
                                 void freefunc(void *), void *freefunc_arg);

extern char *nb_map(netbuf_t nb);
extern netbuf_t nb_alloc(unsigned size);
extern void nb_free(netbuf_t nb);
extern unsigned nb_size(netbuf_t nb);
extern int nb_shrink_top(netbuf_t nb, unsigned size);
extern int nb_shrink_bot(netbuf_t nb, unsigned size);

#endif
