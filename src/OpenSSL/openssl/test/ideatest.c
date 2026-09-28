/* The IDEA sources in this tree are empty files and it builds no-idea, which
 * keeps crypto/idea from linking its ideatest.c here.  This is upstream
 * ideatest.c's NO_IDEA branch, so the test directory still builds. */
#include <stdio.h>

int main(int argc, char *argv[])
	{
	printf("No IDEA support\n");
	return(0);
	}
