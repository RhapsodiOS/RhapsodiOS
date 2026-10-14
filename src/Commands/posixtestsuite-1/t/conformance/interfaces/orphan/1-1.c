#include <unistd.h>
int main(void)
{
	if (fork() == 0) {
		execl("/bin/sleep", "sleep", "77", (char *)0);
		_exit(1);
	}
	return 0;
}
