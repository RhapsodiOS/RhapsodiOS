#include <signal.h>
int main(void) { kill(0, SIGKILL); return 0; }
