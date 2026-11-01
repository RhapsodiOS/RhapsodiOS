#ifndef NSProcessInfoPrivate_h
#define NSProcessInfoPrivate_h

#if defined(__ppc__) || defined(__POWERPC__)
typedef double NSProcessInfoCurrentTime;
#else
typedef long double NSProcessInfoCurrentTime;
#endif

extern NSProcessInfoCurrentTime _NSCurrentTime(void);

#endif
