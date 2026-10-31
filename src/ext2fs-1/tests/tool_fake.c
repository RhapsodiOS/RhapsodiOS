/* Private argv/status child for production tool tests. */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
int main(int argc,char **argv) {
 FILE *f; int i; const char *path=getenv("TOOL_LOG");
 if (path) { f=fopen(path,"wb"); if(!f)return 8;
  for(i=0;i<argc;i++) fwrite(argv[i],1,strlen(argv[i])+1,f);
  fclose(f);
 }
 if(getenv("TOOL_SIGNAL")) raise(SIGTERM);
 return getenv("TOOL_EXIT")?atoi(getenv("TOOL_EXIT")):0;
}
