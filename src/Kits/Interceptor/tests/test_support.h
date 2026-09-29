#ifndef _INTERCEPTOR_TEST_SUPPORT_H_
#define _INTERCEPTOR_TEST_SUPPORT_H_

int TestCheck(int condition, const char *name);
int TestFinish(void);
void *TestLoadSelectedFramework(void);

#endif
