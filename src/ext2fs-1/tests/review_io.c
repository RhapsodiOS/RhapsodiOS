/* Focused native final-review regressions. Only private test volumes. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <dev/disk.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"review_io:%d: %s errno=%d\n",__LINE__,#x,errno);return 1;}}while(0)
static char data[4096];
static int makefile(const char *name,int size){int fd,n;CHECK((fd=open(name,O_CREAT|O_EXCL|O_RDWR,0666))>=0);memset(data,'Q',sizeof(data));for(n=0;n<size;n+=sizeof(data))CHECK(write(fd,data,sizeof(data))==sizeof(data));CHECK(fsync(fd)==0 && close(fd)==0);return 0;}
static int prepare(void){struct timeval times[2];struct stat st;int fd;CHECK(makefile("buffered",4096)==0 && makefile("mapped",4096)==0);CHECK(symlink("buffered","short")==0);times[0].tv_sec=times[1].tv_sec=100;times[0].tv_usec=times[1].tv_usec=0;CHECK(utimes("buffered",times)==0 && utimes("mapped",times)==0);CHECK(lstat("short",&st)==0);CHECK((fd=open("link-inode",O_CREAT|O_EXCL|O_WRONLY,0600))>=0);sprintf(data,"%lu\n",(unsigned long)st.st_ino);CHECK(write(fd,data,strlen(data))==strlen(data));CHECK(fsync(fd)==0 && close(fd)==0);puts("WAVE_OK prepared-old-atime");return 0;}
static int access_files(int readonly){int fd,held,i;char *pages;struct stat before[3],after;struct timeval times[2];const char *names[]={"buffered","mapped","short"};
 for(i=0;i<3;i++)CHECK(lstat(names[i],&before[i])==0);
 CHECK((fd=open("buffered",O_RDONLY))>=0);CHECK(read(fd,data,4)==4 && !memcmp(data,"QQQQ",4));if(!readonly)CHECK(fsync(fd)==0);CHECK(close(fd)==0);
 CHECK((fd=open("mapped",O_RDONLY))>=0);pages=mmap(0,4096,PROT_READ,MAP_SHARED,fd,0);CHECK(pages!=(void *)-1 && pages[0]=='Q');
 /* Establishing the mapping may access the inode through the pager first. */
 if(!readonly){CHECK(fsync(fd)==0);times[0].tv_sec=times[1].tv_sec=100;times[0].tv_usec=times[1].tv_usec=0;CHECK(utimes("mapped",times)==0 && fsync(fd)==0);CHECK(lstat("mapped",&after)==0 && after.st_atime==100);puts("WAVE_OK mapped-atime-reset-after-pager");}
 /* A second open enrolls the existing pager, exercising the direct MapFS route. */
 CHECK((held=open("mapped",O_RDONLY))>=0);CHECK(read(held,data,4)==4 && !memcmp(data,"QQQQ",4));if(!readonly)CHECK(fsync(held)==0);CHECK(close(held)==0 && munmap(pages,4096)==0 && close(fd)==0);
 CHECK(readlink("short",data,sizeof(data))==8 && !memcmp(data,"buffered",8));
 if(readonly)for(i=0;i<3;i++){CHECK(lstat(names[i],&after)==0);CHECK(after.st_atime==before[i].st_atime);}
 puts(readonly?"WAVE_OK readonly-access":"WAVE_OK buffered-mapped-inline-access");return 0;}
static int verify(void){struct stat st;int i;const char *names[]={"buffered","mapped","short"};for(i=0;i<3;i++){CHECK(lstat(names[i],&st)==0 && st.st_atime>100);printf("ATIME %s %ld\n",names[i],(long)st.st_atime);}CHECK(access_files(1)==0);puts("WAVE_OK persisted-atime");return 0;}
static int reserve(void){struct statfs fs;struct stat st;int fd,userfd,i,status;pid_t child;long free_before;
 CHECK(chmod(".",0777)==0);CHECK((userfd=open("reserve-user",O_CREAT|O_EXCL|O_RDWR,0666))>=0);CHECK(fchmod(userfd,0666)==0 && close(userfd)==0);
 CHECK((fd=open("reserve-root",O_CREAT|O_EXCL|O_RDWR,0600))>=0);memset(data,'R',sizeof(data));
 for(i=0;i<4096;i++){CHECK(fstatfs(fd,&fs)==0);if(fs.f_bavail==0)break;CHECK(write(fd,data,4096)==4096);}
 CHECK(i<4096 && fs.f_bfree>4);free_before=fs.f_bfree;CHECK(write(fd,data,4096)==4096 && fsync(fd)==0 && fstatfs(fd,&fs)==0);CHECK(fs.f_bfree<free_before && fs.f_bavail==0);printf("RESERVE root-crossed free=%ld available=%ld\n",(long)fs.f_bfree,(long)fs.f_bavail);
 CHECK((child=fork())>=0);if(child==0){if(setgid(501)||setuid(501))_exit(2);userfd=open("reserve-user",O_WRONLY);if(userfd<0)_exit(3);errno=0;if(write(userfd,data,1024)!=-1 || errno!=ENOSPC)_exit(4);if(fstat(userfd,&st)||st.st_size!=0)_exit(5);close(userfd);_exit(0);}
 CHECK(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0);CHECK(close(fd)==0 && unlink("reserve-root")==0);puts("WAVE_OK nonroot-reserve-after-root");return 0;}
static int integrity(void){int fd;struct stat st;CHECK(makefile("truncate-proof",282624)==0);CHECK((fd=open("truncate-proof",O_RDWR))>=0);CHECK(ftruncate(fd,275456)==0 && fsync(fd)==0);CHECK(ftruncate(fd,13312)==0 && fsync(fd)==0);CHECK(lseek(fd,12288,SEEK_SET)==12288 && read(fd,data,4)==4 && !memcmp(data,"QQQQ",4));CHECK(ftruncate(fd,0)==0 && fsync(fd)==0);CHECK(fstat(fd,&st)==0 && st.st_size==0 && st.st_blocks==0);CHECK(close(fd)==0);puts("WAVE_OK valid-double-single-full-truncate");return 0;}
static unsigned long le32(unsigned char *p){return (unsigned long)p[0]|((unsigned long)p[1]<<8)|((unsigned long)p[2]<<16)|((unsigned long)p[3]<<24);}
static void put32(unsigned char *p,unsigned long v){p[0]=v;p[1]=v>>8;p[2]=v>>16;p[3]=v>>24;}
/* Offline fixture mutation only, with exact selected-volume and inode guards. */
static int patch(const char *raw,unsigned long ino,int bad){struct disk_partition_info part;unsigned char sb[1024],gd[1024],block[1024];unsigned long bcount,ipg,index,table,off;int fd;
 CHECK(!strcmp(raw,"/dev/rhd1a") || !strcmp(raw,"/dev/rhd3a"));CHECK((fd=open(raw,O_RDWR))>=0);CHECK(ioctl(fd,DKIOCGPARTINFO,&part)==0 && (part.block_size==512 || part.block_size==1024) && (unsigned long)part.block_size*part.block_count==16777216UL);
 CHECK(lseek(fd,1024,SEEK_SET)==1024 && read(fd,sb,1024)==1024);CHECK(sb[56]==0x53 && sb[57]==0xef && le32(sb+24)==0);bcount=le32(sb+4);ipg=le32(sb+40);CHECK(bcount==15360 && ino>=12 && ino<=le32(sb) && (ino-1)/ipg==0);
 CHECK(lseek(fd,2048,SEEK_SET)==2048 && read(fd,gd,1024)==1024);table=le32(gd+8);index=ino-1;off=(table+index/8)*1024;CHECK(off<15360*1024);CHECK(lseek(fd,off,SEEK_SET)==off && read(fd,block,1024)==1024);index=(index%8)*128;
 if(bad){CHECK((block[index+1]&0xf0)==0x80 && le32(block+index+4)==14336 && le32(block+index+28)==0);put32(block+index+88,bcount);memset(data,0x5a,1024);CHECK(lseek(fd,bcount*1024,SEEK_SET)==bcount*1024 && write(fd,data,1024)==1024);}
 else{CHECK((block[index+1]&0xf0)==0xa0 && le32(block+index+4)==8 && le32(block+index+28)==0);put32(block+index+8,100);}
 CHECK(lseek(fd,off,SEEK_SET)==off && write(fd,block,1024)==1024 && fsync(fd)==0 && close(fd)==0);puts(bad?"WAVE_OK corrupt-root-fixture":"WAVE_OK old-inline-atime-fixture");return 0;}
static int bad_prepare(void){struct stat st;int fd;CHECK((fd=open("bad-root",O_CREAT|O_EXCL|O_RDWR,0600))>=0);CHECK(ftruncate(fd,14336)==0 && fsync(fd)==0 && fstat(fd,&st)==0 && close(fd)==0);printf("%lu\n",(unsigned long)st.st_ino);return 0;}
static int bad_run(const char *raw){struct stat st;int fd,r,i;CHECK((fd=open("bad-root",O_RDWR))>=0);errno=0;CHECK(ftruncate(fd,13312)==-1 && errno==EIO);CHECK(fstat(fd,&st)==0 && st.st_size==14336);errno=0;CHECK(fsync(fd)==-1 && errno==EIO);r=close(fd);printf("BAD_ROOT close=%d errno=%d\n",r,errno);CHECK((fd=open(raw,O_RDONLY))>=0);CHECK(lseek(fd,15360*1024,SEEK_SET)==15360*1024 && read(fd,data,1024)==1024);for(i=0;i<1024;i++)CHECK((unsigned char)data[i]==0x5a);CHECK(close(fd)==0);puts("WAVE_OK corrupt-root-EIO-outside-unchanged");return 0;}
static int ufs(int verify_only){struct statfs fs;int fd;char *pages;CHECK(statfs(".",&fs)==0 && !strcmp(fs.f_fstypename,"ufs"));if(!verify_only){CHECK(makefile("ufs-mapped",8192)==0);CHECK((fd=open("ufs-mapped",O_RDWR))>=0);pages=mmap(0,8192,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);CHECK(pages!=(void *)-1);memcpy(pages+4093,"mapfs",5);CHECK(fsync(fd)==0 && munmap(pages,8192)==0 && close(fd)==0);}CHECK((fd=open("ufs-mapped",O_RDONLY))>=0);CHECK(lseek(fd,4093,SEEK_SET)==4093 && read(fd,data,5)==5 && !memcmp(data,"mapfs",5));CHECK(close(fd)==0);puts("WAVE_OK UFS-mapped-fsync-readback");return 0;}
int main(int argc,char **argv){setbuf(stdout,NULL);CHECK(argc>=3);if(!strcmp(argv[1],"patch-link")||!strcmp(argv[1],"patch-bad")){CHECK(argc==4);return patch(argv[2],strtoul(argv[3],NULL,10),!strcmp(argv[1],"patch-bad"));}CHECK(chdir(argv[2])==0);if(!strcmp(argv[1],"prepare"))return prepare();if(!strcmp(argv[1],"access"))return access_files(0);if(!strcmp(argv[1],"verify"))return verify();if(!strcmp(argv[1],"readonly"))return access_files(1);if(!strcmp(argv[1],"reserve"))return reserve();if(!strcmp(argv[1],"integrity"))return integrity();if(!strcmp(argv[1],"bad-prepare"))return bad_prepare();if(!strcmp(argv[1],"bad-run")){CHECK(argc==4);return bad_run(argv[3]);}if(!strcmp(argv[1],"ufs-write"))return ufs(0);if(!strcmp(argv[1],"ufs-read"))return ufs(1);return 2;}
