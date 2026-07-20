#include "index.h"
#include "mkapk.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	if (argc >= 2 && !strcmp(argv[1], "mkapk")) {
		if (argc != 5) {
			fprintf(stderr,
			    "usage: rhap-build mkapk <PKGINFO> <staging-root> <out.apk>\n");
			return 2;
		}
		return mkapk(argv[2], argv[3], argv[4]);
	}

	if (argc >= 2 && !strcmp(argv[1], "index")) {
		if (argc != 3) {
			fprintf(stderr, "usage: rhap-build index <repo-dir>\n");
			return 2;
		}
		return index_apk_repo(argv[2]);
	}

	fprintf(stderr, "rhap-build: incomplete build\n");
	return 2;
}
