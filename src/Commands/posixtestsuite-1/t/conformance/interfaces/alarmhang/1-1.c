#include <signal.h>
static void on_alarm(int sig) { }
int main(void) { signal(SIGALRM, on_alarm); for (;;) ; }
