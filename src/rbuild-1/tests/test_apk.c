#include "apk.h"
#include "exec.h"
#include "test.h"

#include <errno.h>
#include <sys/types.h>
#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <utime.h>
#include <unistd.h>

#define ENTRY_BAD_CHECKSUM 1
#define ENTRY_BAD_SIZE 2
#define ENTRY_TRUNCATED 4
#define ENTRY_OLDGNU 8
#define ENTRY_BAD_DEVICE 16
#define ENTRY_MODE_0750 32
#define ENTRY_PREFIX 64     /* name before its last '/' goes in ustar prefix */
#define ENTRY_V7 128        /* no magic or version: old v7 tar header */
#define ENTRY_NUL_SIZE 256  /* size field starts with a NUL */
#define ENTRY_LEADING_ZEROS 512 /* 1024 zero bytes before this header */

typedef struct {
    const char *name;
    char type;
    const char *linkname;
    const char *data;
    int flags;
    size_t binary_size;
} TarEntry;

void apk_test_set_quarantine_hook(void (*hook)(void));
void apk_test_set_quarantine_pre_link_hook(void (*hook)(void));
void apk_test_set_quarantine_after_publish_hook(void (*hook)(void));
void apk_test_set_readdir_failure(int calls_before_failure);

static int quarantine_ready_fd;
static int quarantine_continue_fd;

static void quarantine_barrier(void) {
    char byte;
    if (write(quarantine_ready_fd, "r", 1) != 1) _exit(3);
    if (read(quarantine_continue_fd, &byte, 1) != 1) _exit(4);
}

static void write_text(const char *path, const char *text) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fputs(text, fp);
    fclose(fp);
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static int quarantine_temp_count(const char *directory) {
    DIR *dir = opendir(directory);
    struct dirent *entry;
    int count = 0;
    CHECK(dir != 0);
    if (dir == 0) return -1;
    while ((entry = readdir(dir)) != 0)
        if (strncmp(entry->d_name, ".rbuild-quarantine-", 19) == 0)
            count++;
    closedir(dir);
    return count;
}

static void put_octal(char *field, size_t width, unsigned long value) {
    char number[32];
    size_t length;

    sprintf(number, "%lo", value);
    length = strlen(number);
    memset(field, '0', width);
    field[width - 1] = '\0';
    if (length < width) memcpy(field + width - 1 - length, number, length);
}

static void write_zeros(FILE *fp, size_t count) {
    char zeros[512];
    memset(zeros, 0, sizeof(zeros));
    while (count > 0) {
        size_t chunk = count > sizeof(zeros) ? sizeof(zeros) : count;
        CHECK(fwrite(zeros, 1, chunk, fp) == chunk);
        count -= chunk;
    }
}

static int write_tar(const char *path, const TarEntry *entries,
                     size_t count) {
    FILE *fp;
    size_t i;

    fp = fopen(path, "wb");
    if (fp == 0) return 1;
    for (i = 0; i < count; i++) {
        char header[512];
        const char *data = entries[i].data ? entries[i].data : "";
        size_t data_size = entries[i].binary_size ? entries[i].binary_size : strlen(data);
        unsigned long stored_size = (unsigned long)data_size;
        unsigned long checksum = 0;
        size_t j;

        if (entries[i].flags & ENTRY_TRUNCATED) stored_size += 17;
        memset(header, 0, sizeof(header));
        strncpy(header, entries[i].name, 100);
        if (entries[i].flags & ENTRY_PREFIX) {
            const char *slash = strrchr(entries[i].name, '/');
            memset(header, 0, 100);
            strncpy(header, slash + 1, 100);
            memcpy(header + 345, entries[i].name,
                   (size_t)(slash - entries[i].name));
        }
        put_octal(header + 100, 8,
                  (entries[i].flags & ENTRY_MODE_0750) ? 0750 : 0644);
        put_octal(header + 108, 8, 0);
        put_octal(header + 116, 8, 0);
        put_octal(header + 124, 12, stored_size);
        put_octal(header + 136, 12, 0);
        memset(header + 148, ' ', 8);
        header[156] = entries[i].type;
        if (entries[i].linkname != 0)
            strncpy(header + 157, entries[i].linkname, 100);
        memcpy(header + 257, "ustar", 5);
        memcpy(header + 263, "00", 2);
        if (entries[i].type == '3' || entries[i].type == '4') {
            put_octal(header + 329, 8, 1);
            put_octal(header + 337, 8, 3);
        }
        if (entries[i].flags & ENTRY_BAD_DEVICE) header[329] = 'x';
        if (entries[i].flags & ENTRY_OLDGNU) {
            header[262] = ' ';
            header[263] = ' ';
            header[264] = '\0';
        }
        if (entries[i].flags & ENTRY_V7) memset(header + 257, 0, 8);
        if (entries[i].flags & ENTRY_BAD_SIZE) header[124] = 'x';
        if (entries[i].flags & ENTRY_NUL_SIZE) header[124] = '\0';
        for (j = 0; j < sizeof(header); j++)
            checksum += (unsigned char)header[j];
        put_octal(header + 148, 7, checksum);
        header[155] = ' ';
        if (entries[i].flags & ENTRY_BAD_CHECKSUM) header[0] ^= 1;
        if (entries[i].flags & ENTRY_LEADING_ZEROS) write_zeros(fp, 1024);
        if (fwrite(header, 1, sizeof(header), fp) != sizeof(header)) {
            fclose(fp);
            return 1;
        }
        if (data_size != 0 && fwrite(data, 1, data_size, fp) != data_size) {
            fclose(fp);
            return 1;
        }
        if (entries[i].flags & ENTRY_TRUNCATED) {
            fclose(fp);
            return 0;
        }
        write_zeros(fp, (512 - (data_size % 512)) % 512);
    }
    write_zeros(fp, 1024);
    return fclose(fp) != 0;
}

static int gzip_file(const char *input, const char *output) {
    pid_t pid;
    int fd;
    int status;

    fd = open(output, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 1;
    pid = fork();
    if (pid < 0) {
        close(fd);
        return 1;
    }
    if (pid == 0) {
        char *argv[5];
        if (dup2(fd, STDOUT_FILENO) < 0) _exit(127);
        close(fd);
        argv[0] = "/usr/bin/gzip";
        argv[1] = "-n";
        argv[2] = "-c";
        argv[3] = (char *)input;
        argv[4] = 0;
        execv(argv[0], argv);
        _exit(127);
    }
    close(fd);
    if (waitpid(pid, &status, 0) < 0) return 1;
    return status != 0;
}

static int make_apk(const char *apk, const TarEntry *entries, size_t count) {
    char tarpath[192];
    int result;

    sprintf(tarpath, "%s.tar", apk);
    result = write_tar(tarpath, entries, count);
    if (result == 0) result = gzip_file(tarpath, apk);
    remove(tarpath);
    return result;
}

static int file_has_line(const char *path, const char *wanted) {
    FILE *fp;
    char line[256];
    int found = 0;

    fp = fopen(path, "r");
    if (fp == 0) return 0;
    while (fgets(line, sizeof(line), fp) != 0) {
        size_t length = strlen(line);
        if (length != 0 && line[length - 1] == '\n') line[length - 1] = '\0';
        if (strcmp(line, wanted) == 0) found = 1;
    }
    fclose(fp);
    return found;
}

static int file_has_sequence(const char *path, const char *a, const char *b,
                             const char *c, const char *d) {
    FILE *fp;
    char line[256];
    const char *wanted[4];
    int matched = 0;

    wanted[0] = a;
    wanted[1] = b;
    wanted[2] = c;
    wanted[3] = d;
    fp = fopen(path, "r");
    if (fp == 0) return 0;
    while (fgets(line, sizeof(line), fp) != 0) {
        size_t length = strlen(line);
        if (length != 0 && line[length - 1] == '\n') line[length - 1] = '\0';
        if (wanted[matched] == 0 || strcmp(line, wanted[matched]) == 0)
            matched++;
        else matched = strcmp(line, wanted[0]) == 0 ? 1 : 0;
        if (matched == 4) break;
    }
    fclose(fp);
    return matched == 4;
}

static int file_equals(const char *path, const char *wanted) {
    FILE *fp;
    char buffer[128];
    size_t length;

    fp = fopen(path, "r");
    if (fp == 0) return 0;
    length = fread(buffer, 1, sizeof(buffer) - 1, fp);
    buffer[length] = '\0';
    fclose(fp);
    return strcmp(buffer, wanted) == 0;
}

static void write_wrapper(const char *path, const char *log,
                          const char *program) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fprintf(fp, "#!/bin/sh\nfor arg in \"$@\"; do echo \"$arg\"; done >> %s\n",
            log);
    fprintf(fp, "exec %s \"$@\"\n", program);
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void write_second_call_failure(const char *path, const char *count) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fprintf(fp, "#!/bin/sh\n");
    fprintf(fp, "if test -f %s; then n=`cat %s`; else n=0; fi\n",
            count, count);
    fprintf(fp, "n=`expr $n + 1`; echo $n > %s\n", count);
    fprintf(fp, "/usr/bin/gzip \"$@\"\nstatus=$?\n");
    fprintf(fp, "if test \"$n\" -eq 2; then exit 9; fi\nexit $status\n");
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void write_tar_failure(const char *path) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fputs("#!/bin/sh\n/usr/bin/tar \"$@\"\nexit 9\n", fp);
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void write_mutating_gzip(const char *path, const char *target) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fputs("#!/bin/sh\n/usr/bin/gzip \"$@\"\nstatus=$?\n", fp);
    fprintf(fp, "sleep 1\ntouch %s\nexit $status\n", target);
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void write_replacing_gzip(const char *path, const char *count,
                                 const char *original,
                                 const char *replacement) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fprintf(fp, "#!/bin/sh\n");
    fprintf(fp, "if test -f %s; then n=`cat %s`; else n=0; fi\n",
            count, count);
    fprintf(fp, "n=`expr $n + 1`; echo $n > %s\n", count);
    fprintf(fp, "if test \"$n\" -eq 3; then mv %s %s; fi\n",
            replacement, original);
    fputs("exec /usr/bin/gzip \"$@\"\n", fp);
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void write_inplace_replacing_gzip(const char *path, const char *count,
                                         const char *original,
                                         const char *replacement,
                                         const char *timestamp) {
    FILE *fp = fopen(path, "w");
    CHECK(fp != 0);
    if (fp == 0) return;
    fprintf(fp, "#!/bin/sh\n");
    fprintf(fp, "if test -f %s; then n=`cat %s`; else n=0; fi\n",
            count, count);
    fprintf(fp, "n=`expr $n + 1`; echo $n > %s\n", count);
    fprintf(fp, "if test \"$n\" -eq 3; then cp %s %s; touch -r %s %s; fi\n",
            replacement, original, timestamp, original);
    fputs("exec /usr/bin/gzip \"$@\"\n", fp);
    fclose(fp);
    CHECK_INT(chmod(path, 0700), 0);
}

static void init_toolchain(Toolchain *tc) {
    toolchain_init(tc);
    tc->tar = "/usr/bin/tar";
    tc->gzip = "/usr/bin/gzip";
}

static void make_scratch(char *path, size_t capacity, const char *tag) {
    static int serial = 0;
    int attempt;

    for (attempt = 0; attempt < 100; attempt++) {
        sprintf(path, "/tmp/rbuild-apk-test-%s-%ld-%ld-%d", tag,
                (long)getpid(), (long)time(0), serial++);
        if (strlen(path) + 1 <= capacity && mkdir(path, 0700) == 0) return;
        if (errno != EEXIST) break;
    }
    CHECK(0);
}

TEST(test_validate_extract_and_quarantine) {
    char scratch[128];
    char good[160];
    char bad[160];
    char invalid[176];
    char missing[160];
    char missing_invalid[176];
    char root[160];
    char extracted[192];
    struct stat st;
    Toolchain tc;
    TarEntry good_entries[] = {
        { "./.PKGINFO", '0', 0, "pkgname = probe\n", 0 },
        { "./usr/bin/probe", '0', 0, "probe\n", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "basic");
    sprintf(good, "%s/good.apk", scratch);
    sprintf(bad, "%s/bad.apk", scratch);
    sprintf(invalid, "%s.invalid", bad);
    sprintf(missing, "%s/missing.apk", scratch);
    sprintf(missing_invalid, "%s.invalid", missing);
    sprintf(root, "%s/root", scratch);
    sprintf(extracted, "%s/usr/bin/probe", root);
    CHECK_INT(make_apk(good, good_entries, 2), 0);
    write_text(bad, "not an apk\n");
    init_toolchain(&tc);

    CHECK_INT(apk_validate(0, &tc), 1);
    CHECK_INT(apk_validate("", &tc), 1);
    CHECK_INT(apk_validate(good, 0), 1);
    CHECK_INT(apk_validate(good, &tc), 0);
    CHECK_INT(apk_validate(bad, &tc), 1);
    CHECK_INT(apk_extract(good, root, &tc), 0);
    CHECK(stat(extracted, &st) == 0 && S_ISREG(st.st_mode));
    CHECK_INT(apk_quarantine(bad), 0);
    CHECK(!file_exists(bad));
    CHECK(stat(invalid, &st) == 0 && S_ISREG(st.st_mode));

    write_text(bad, "still bad\n");
    CHECK_INT(apk_quarantine(bad), 1);
    CHECK(file_exists(bad));
    CHECK(file_equals(bad, "still bad\n"));
    CHECK(file_equals(invalid, "not an apk\n"));
    CHECK_INT(apk_quarantine(0), 1);
    CHECK_INT(apk_quarantine(missing), 1);
    CHECK(!file_exists(missing_invalid));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_configured_tools_are_used_without_tar_z) {
    char scratch[128];
    char apk[160];
    char root[160];
    char gzip_wrapper[160];
    char tar_wrapper[160];
    char gzip_log[160];
    char tar_log[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "pkgname = configured\n", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "tools");
    sprintf(apk, "%s/good.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    sprintf(tar_wrapper, "%s/tar", scratch);
    sprintf(gzip_log, "%s/gzip.log", scratch);
    sprintf(tar_log, "%s/tar.log", scratch);
    CHECK_INT(make_apk(apk, entries, 1), 0);
    write_wrapper(gzip_wrapper, gzip_log, "/usr/bin/gzip");
    write_wrapper(tar_wrapper, tar_log, "/usr/bin/tar");
    toolchain_init(&tc);
    tc.gzip = gzip_wrapper;
    tc.tar = tar_wrapper;

    CHECK_INT(apk_validate(apk, &tc), 0);
    CHECK_INT(apk_extract(apk, root, &tc), 0);
    CHECK(file_has_line(gzip_log, "-dc"));
    CHECK(file_has_line(tar_log, "-tf"));
    CHECK(file_has_line(tar_log, "-xf"));
    CHECK(file_has_sequence(tar_log, "-C", 0, "-xf", "-"));
    CHECK(!file_has_line(tar_log, "-tzf"));
    CHECK(!file_has_line(tar_log, "-xzf"));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void check_invalid_apk(const char *path, Toolchain *tc,
                              TarEntry *entries, size_t count) {
    CHECK_INT(make_apk(path, entries, count), 0);
    CHECK_INT(apk_validate(path, tc), 1);
}

TEST(test_validation_rejects_unsafe_or_malformed_members) {
    char scratch[128];
    char apk[160];
    Toolchain tc;
    TarEntry absolute[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "/etc/evil", '0', 0, "evil", 0 }
    };
    TarEntry traversal[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "../evil", '0', 0, "evil", 0 }
    };
    TarEntry pivot[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "usr", '2', "safe", "", 0 },
        { "usr/bin/evil", '0', 0, "evil", 0 }
    };
    TarEntry escaping_symlink[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "usr/link", '2', "../../etc", "", 0 }
    };
    TarEntry escaping_hardlink[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "usr/link", '1', "../etc/passwd", "", 0 }
    };
    TarEntry symlink_metadata[] = {
        { ".PKGINFO", '2', "real", "", 0 }
    };
    TarEntry duplicate_metadata[] = {
        { ".PKGINFO", '0', 0, "one", 0 },
        { "./.PKGINFO", '0', 0, "two", 0 }
    };
    TarEntry missing_metadata[] = {
        { "usr/bin/probe", '0', 0, "probe", 0 }
    };
    TarEntry bad_checksum[] = {
        { ".PKGINFO", '0', 0, "ok", ENTRY_BAD_CHECKSUM }
    };
    TarEntry bad_size[] = {
        { ".PKGINFO", '0', 0, "ok", ENTRY_BAD_SIZE }
    };
    TarEntry truncated[] = {
        { ".PKGINFO", '0', 0, "short", ENTRY_TRUNCATED }
    };
    TarEntry device_data[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "dev/bad", '3', 0, "data", 0 }
    };
    TarEntry bad_device[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "dev/bad", '4', 0, "", ENTRY_BAD_DEVICE }
    };

    make_scratch(scratch, sizeof(scratch), "invalid");
    sprintf(apk, "%s/test.apk", scratch);
    init_toolchain(&tc);
    check_invalid_apk(apk, &tc, absolute, 2);
    check_invalid_apk(apk, &tc, traversal, 2);
    check_invalid_apk(apk, &tc, pivot, 3);
    check_invalid_apk(apk, &tc, escaping_symlink, 2);
    check_invalid_apk(apk, &tc, escaping_hardlink, 2);
    check_invalid_apk(apk, &tc, symlink_metadata, 1);
    check_invalid_apk(apk, &tc, duplicate_metadata, 2);
    check_invalid_apk(apk, &tc, missing_metadata, 1);
    check_invalid_apk(apk, &tc, bad_checksum, 1);
    check_invalid_apk(apk, &tc, bad_size, 1);
    check_invalid_apk(apk, &tc, truncated, 1);
    check_invalid_apk(apk, &tc, device_data, 2);
    check_invalid_apk(apk, &tc, bad_device, 2);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_metadata_spelling_variants_are_accepted) {
    char scratch[128];
    char apk[160];
    Toolchain tc;
    TarEntry plain[] = { { ".PKGINFO", '0', 0, "plain", 0 } };
    TarEntry dotted[] = { { "./.PKGINFO", '\0', 0, "dotted", 0 } };

    make_scratch(scratch, sizeof(scratch), "metadata");
    sprintf(apk, "%s/test.apk", scratch);
    init_toolchain(&tc);
    CHECK_INT(make_apk(apk, plain, 1), 0);
    CHECK_INT(apk_validate(apk, &tc), 0);
    CHECK_INT(make_apk(apk, dotted, 1), 0);
    CHECK_INT(apk_validate(apk, &tc), 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_rejects_oldgnu_header_layout) {
    char scratch[128];
    char apk[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "oldgnu", ENTRY_OLDGNU }
    };

    make_scratch(scratch, sizeof(scratch), "oldgnu");
    sprintf(apk, "%s/test.apk", scratch);
    CHECK_INT(make_apk(apk, entries, 1), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_validate(apk, &tc), 1);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_accepts_character_device_member) {
    char scratch[128];
    char apk[160];
    char root[160];
    char device[192];
    char block_device[192];
    char device_dir[192];
    struct stat st;
    struct stat null_stat;
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "devices", 0 },
        { "dev/probe", '3', 0, "", 0 },
        { "dev/probeb", '4', 0, "", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "device");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(device, "%s/dev/probe", root);
    sprintf(block_device, "%s/dev/probeb", root);
    sprintf(device_dir, "%s/dev", root);
    CHECK_INT(make_apk(apk, entries, 3), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_validate(apk, &tc), 0);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", device_dir, (char *)0), 0);
    CHECK_INT(stat("/dev/null", &null_stat), 0);
    if (mknod(device, S_IFCHR | 0600, null_stat.st_rdev) == 0) {
        CHECK_INT(unlink(device), 0);
        CHECK_INT(apk_extract(apk, root, &tc), 0);
        CHECK(lstat(device, &st) == 0 && S_ISCHR(st.st_mode));
        CHECK(lstat(block_device, &st) == 0 && S_ISBLK(st.st_mode));
    } else if (errno == EPERM || errno == EACCES) {
        printf("# SKIP device restoration denied by host capability\n");
    } else {
        CHECK(0);
    }
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_preserves_hard_links) {
    char scratch[128];
    char apk[160];
    char root[160];
    char original[192];
    char linked[192];
    struct stat original_stat;
    struct stat linked_stat;
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "hardlinks", 0 },
        { "usr/bin/original", '0', 0, "shared-content", 0 },
        { "usr/bin/linked", '1', "usr/bin/original", "", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "hardlink");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(original, "%s/usr/bin/original", root);
    sprintf(linked, "%s/usr/bin/linked", root);
    CHECK_INT(make_apk(apk, entries, 3), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_extract(apk, root, &tc), 0);
    CHECK_INT(lstat(original, &original_stat), 0);
    CHECK_INT(lstat(linked, &linked_stat), 0);
    CHECK(original_stat.st_ino == linked_stat.st_ino);
    CHECK(original_stat.st_nlink >= 2 && linked_stat.st_nlink >= 2);
    CHECK(file_equals(original, "shared-content"));
    CHECK(file_equals(linked, "shared-content"));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_implicit_directories_preserve_existing_metadata) {
    char scratch[128];
    char apk[160];
    char root[160];
    char parent[192];
    char file[224];
    struct stat before;
    struct stat after;
    struct utimbuf times;
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "implicit", 0 },
        { "usr/share/deep/file", '0', 0, "payload", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "implicit-dir");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(parent, "%s/usr/share", root);
    sprintf(file, "%s/deep/file", parent);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", parent, (char *)0), 0);
    CHECK_INT(chmod(parent, 0711), 0);
    times.actime = 123456789;
    times.modtime = 123456789;
    CHECK_INT(utime(parent, &times), 0);
    CHECK_INT(lstat(parent, &before), 0);
    CHECK_INT(make_apk(apk, entries, 2), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_extract(apk, root, &tc), 0);
    CHECK_INT(lstat(parent, &after), 0);
    CHECK((after.st_mode & 07777) == (before.st_mode & 07777));
    CHECK(after.st_mtime == before.st_mtime);
    CHECK(file_equals(file, "payload"));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_explicit_directory_metadata_is_applied) {
    char scratch[128];
    char apk[160];
    char root[160];
    char parent[192];
    struct stat st;
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "explicit", 0 },
        { "usr/share", '5', 0, "", ENTRY_MODE_0750 },
        { "usr/share/file", '0', 0, "payload", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "explicit-dir");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(parent, "%s/usr/share", root);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", parent, (char *)0), 0);
    CHECK_INT(chmod(parent, 0711), 0);
    CHECK_INT(make_apk(apk, entries, 3), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_extract(apk, root, &tc), 0);
    CHECK_INT(lstat(parent, &st), 0);
    CHECK((st.st_mode & 07777) == 0750);
    CHECK(st.st_mtime == 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_readdir_error_fails_merge) {
    char scratch[128];
    char apk[160];
    char root[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "readdir", 0 },
        { "usr/share/file", '0', 0, "payload", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "readdir");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    CHECK_INT(make_apk(apk, entries, 2), 0);
    init_toolchain(&tc);
    apk_test_set_readdir_failure(0);
    CHECK_INT(apk_extract(apk, root, &tc), 1);
    apk_test_set_readdir_failure(-1);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_rejects_preexisting_root_symlink) {
    char scratch[128];
    char apk[160];
    char root[160];
    char outside[160];
    char root_usr[192];
    char escaped[192];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "symlink-root", 0 },
        { "usr/bin/probe", '0', 0, "escape", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "rootsym");
    sprintf(apk, "%s/test.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(outside, "%s/outside", scratch);
    sprintf(root_usr, "%s/usr", root);
    sprintf(escaped, "%s/bin/probe", outside);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", root, (char *)0), 0);
    CHECK_INT(exec_runv("/bin/mkdir", "-p", outside, (char *)0), 0);
    CHECK_INT(symlink(outside, root_usr), 0);
    CHECK_INT(make_apk(apk, entries, 2), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_extract(apk, root, &tc), 1);
    CHECK(!file_exists(escaped));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_rejects_unvalidated_archive) {
    char scratch[128];
    char apk[160];
    char root[160];
    char escaped[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "ok", 0 },
        { "../escaped", '0', 0, "bad", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "extract-bad");
    sprintf(apk, "%s/bad.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(escaped, "%s/escaped", scratch);
    CHECK_INT(make_apk(apk, entries, 2), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_extract(apk, root, &tc), 1);
    CHECK(!file_exists(escaped));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_validate_with_closed_standard_fds) {
    char scratch[128];
    char apk[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "low-fd", 0 }
    };
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch), "low-fd");
    sprintf(apk, "%s/test.apk", scratch);
    CHECK_INT(make_apk(apk, entries, 1), 0);
    init_toolchain(&tc);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(STDIN_FILENO);
        _exit(apk_validate(apk, &tc) == 0 ? 0 : 1);
    }
    CHECK(waitpid(pid, &status, 0) == pid && status == 0);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(STDOUT_FILENO);
        _exit(apk_validate(apk, &tc) == 0 ? 0 : 1);
    }
    CHECK(waitpid(pid, &status, 0) == pid && status == 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_checks_both_pipeline_statuses) {
    char scratch[128];
    char apk[160];
    char root[160];
    char gzip_wrapper[160];
    char tar_wrapper[160];
    char count[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "pipeline", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "status");
    sprintf(apk, "%s/good.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    sprintf(tar_wrapper, "%s/tar", scratch);
    sprintf(count, "%s/count", scratch);
    CHECK_INT(make_apk(apk, entries, 1), 0);

    toolchain_init(&tc);
    tc.gzip = gzip_wrapper;
    tc.tar = "/usr/bin/tar";
    write_second_call_failure(gzip_wrapper, count);
    CHECK_INT(apk_extract(apk, root, &tc), 1);

    tc.gzip = "/usr/bin/gzip";
    tc.tar = tar_wrapper;
    write_tar_failure(tar_wrapper);
    CHECK_INT(apk_extract(apk, root, &tc), 1);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_rejects_changed_artifact) {
    char scratch[128];
    char apk[160];
    char root[160];
    char gzip_wrapper[160];
    Toolchain tc;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0, "identity", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "identity");
    sprintf(apk, "%s/good.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    CHECK_INT(make_apk(apk, entries, 1), 0);
    write_mutating_gzip(gzip_wrapper, apk);
    toolchain_init(&tc);
    tc.gzip = gzip_wrapper;
    tc.tar = "/usr/bin/tar";

    CHECK_INT(apk_validate(apk, &tc), 1);
    CHECK_INT(make_apk(apk, entries, 1), 0);
    CHECK_INT(apk_extract(apk, root, &tc), 1);
    CHECK(!file_exists(root));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_does_not_reopen_validated_path) {
    char scratch[128];
    char apk[160];
    char replacement[160];
    char root[160];
    char gzip_wrapper[160];
    char count[160];
    char good_file[192];
    char evil_file[192];
    Toolchain tc;
    TarEntry good[] = {
        { ".PKGINFO", '0', 0, "good", 0 },
        { "usr/bin/good", '0', 0, "validated", 0 }
    };
    TarEntry evil[] = {
        { ".PKGINFO", '0', 0, "evil", 0 },
        { "usr/bin/evil", '0', 0, "replacement", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "reopen");
    sprintf(apk, "%s/package.apk", scratch);
    sprintf(replacement, "%s/replacement.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    sprintf(count, "%s/count", scratch);
    sprintf(good_file, "%s/usr/bin/good", root);
    sprintf(evil_file, "%s/usr/bin/evil", root);
    CHECK_INT(make_apk(apk, good, 2), 0);
    CHECK_INT(make_apk(replacement, evil, 2), 0);
    write_replacing_gzip(gzip_wrapper, count, apk, replacement);
    toolchain_init(&tc);
    tc.gzip = gzip_wrapper;
    tc.tar = "/usr/bin/tar";

    CHECK_INT(apk_extract(apk, root, &tc), 1);
    CHECK(!file_exists(good_file));
    CHECK(!file_exists(evil_file));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_extract_uses_immutable_private_copy) {
    char scratch[128];
    char apk[160];
    char replacement[160];
    char timestamp[160];
    char root[160];
    char gzip_wrapper[160];
    char count[160];
    char good_file[192];
    char evil_file[192];
    Toolchain tc;
    struct stat good_stat;
    struct stat evil_stat;
    TarEntry good[] = {
        { ".PKGINFO", '0', 0, "same", 0 },
        { "usr/bin/good", '0', 0, "validated", 0 }
    };
    TarEntry evil[] = {
        { ".PKGINFO", '0', 0, "same", 0 },
        { "usr/bin/evil", '0', 0, "malicious", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "inplace");
    sprintf(apk, "%s/package.apk", scratch);
    sprintf(replacement, "%s/replacement.apk", scratch);
    sprintf(timestamp, "%s/timestamp", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(gzip_wrapper, "%s/gzip", scratch);
    sprintf(count, "%s/count", scratch);
    sprintf(good_file, "%s/usr/bin/good", root);
    sprintf(evil_file, "%s/usr/bin/evil", root);
    CHECK_INT(make_apk(apk, good, 2), 0);
    CHECK_INT(make_apk(replacement, evil, 2), 0);
    CHECK_INT(stat(apk, &good_stat), 0);
    CHECK_INT(stat(replacement, &evil_stat), 0);
    CHECK_INT(good_stat.st_size, evil_stat.st_size);
    write_text(timestamp, "time");
    CHECK_INT(exec_runv("/usr/bin/touch", "-r", apk, timestamp,
                        (char *)0), 0);
    write_inplace_replacing_gzip(gzip_wrapper, count, apk, replacement,
                                 timestamp);
    toolchain_init(&tc);
    tc.gzip = gzip_wrapper;
    tc.tar = "/usr/bin/tar";

    CHECK_INT(apk_extract(apk, root, &tc), 0);
    CHECK(file_exists(good_file));
    CHECK(!file_exists(evil_file));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_source_replacement_is_preserved) {
    char scratch[128];
    char source[160];
    char saved[160];
    char destination[176];
    int ready[2];
    int proceed[2];
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch), "source-race");
    sprintf(source, "%s/bad.apk", scratch);
    sprintf(saved, "%s/original.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(source, "bad");
    CHECK_INT(pipe(ready), 0);
    CHECK_INT(pipe(proceed), 0);
    quarantine_ready_fd = ready[1];
    quarantine_continue_fd = proceed[0];
    apk_test_set_quarantine_hook(quarantine_barrier);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(ready[0]);
        close(proceed[1]);
        _exit(apk_quarantine(source) == 0 ? 0 : 1);
    }
    close(ready[1]);
    close(proceed[0]);
    {
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
    }
    close(ready[0]);
    CHECK_INT(rename(source, saved), 0);
    write_text(source, "replacement");
    CHECK(write(proceed[1], "c", 1) == 1);
    close(proceed[1]);
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status != 0);
    CHECK(file_equals(source, "replacement"));
    CHECK(file_equals(saved, "bad"));
    CHECK(!file_exists(destination));
    apk_test_set_quarantine_hook(0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_pre_link_source_replacement_rolls_back_destination) {
    char scratch[128];
    char source[160];
    char saved[160];
    char destination[176];
    int ready[2];
    int proceed[2];
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch), "pre-link-race");
    sprintf(source, "%s/bad.apk", scratch);
    sprintf(saved, "%s/original.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(source, "bad");
    CHECK_INT(pipe(ready), 0);
    CHECK_INT(pipe(proceed), 0);
    quarantine_ready_fd = ready[1];
    quarantine_continue_fd = proceed[0];
    apk_test_set_quarantine_pre_link_hook(quarantine_barrier);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(ready[0]);
        close(proceed[1]);
        _exit(apk_quarantine(source) == 0 ? 0 : 1);
    }
    close(ready[1]);
    close(proceed[0]);
    {
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
    }
    close(ready[0]);
    CHECK_INT(rename(source, saved), 0);
    write_text(source, "replacement");
    CHECK(write(proceed[1], "c", 1) == 1);
    close(proceed[1]);
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status != 0);
    CHECK(file_equals(source, "replacement"));
    CHECK(file_equals(saved, "bad"));
    CHECK(!file_exists(destination));
    apk_test_set_quarantine_pre_link_hook(0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_replaced_destination_is_not_overwritten) {
    char scratch[128];
    char source[160];
    char destination[176];
    int ready[2];
    int proceed[2];
    pid_t pid;
    int fd;
    int status;

    make_scratch(scratch, sizeof(scratch), "dest-race");
    sprintf(source, "%s/bad.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(source, "bad");
    CHECK_INT(pipe(ready), 0);
    CHECK_INT(pipe(proceed), 0);
    quarantine_ready_fd = ready[1];
    quarantine_continue_fd = proceed[0];
    apk_test_set_quarantine_hook(quarantine_barrier);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(ready[0]);
        close(proceed[1]);
        _exit(apk_quarantine(source) == 0 ? 0 : 1);
    }
    close(ready[1]);
    close(proceed[0]);
    {
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
    }
    close(ready[0]);
    CHECK_INT(unlink(destination), 0);
    fd = open(destination, O_WRONLY | O_CREAT | O_EXCL, 0600);
    CHECK(fd >= 0);
    if (fd >= 0) CHECK(write(fd, "sentinel", 8) == 8);
    if (fd >= 0) close(fd);
    CHECK(write(proceed[1], "c", 1) == 1);
    close(proceed[1]);
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status != 0);
    CHECK(file_equals(source, "bad"));
    CHECK(file_equals(destination, "sentinel"));
    apk_test_set_quarantine_hook(0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_immediate_publish_replacement_is_preserved) {
    char scratch[128];
    char source[160];
    char destination[176];
    int ready[2];
    int proceed[2];
    pid_t pid;
    int fd;
    int status;

    make_scratch(scratch, sizeof(scratch), "publish-race");
    sprintf(source, "%s/bad.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(source, "bad");
    CHECK_INT(pipe(ready), 0);
    CHECK_INT(pipe(proceed), 0);
    quarantine_ready_fd = ready[1];
    quarantine_continue_fd = proceed[0];
    apk_test_set_quarantine_after_publish_hook(quarantine_barrier);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(ready[0]);
        close(proceed[1]);
        _exit(apk_quarantine(source) == 0 ? 0 : 1);
    }
    close(ready[1]);
    close(proceed[0]);
    {
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
    }
    close(ready[0]);
    CHECK_INT(unlink(destination), 0);
    fd = open(destination, O_WRONLY | O_CREAT | O_EXCL, 0600);
    CHECK(fd >= 0);
    if (fd >= 0) CHECK(write(fd, "competitor", 10) == 10);
    if (fd >= 0) close(fd);
    CHECK(write(proceed[1], "c", 1) == 1);
    close(proceed[1]);
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status != 0);
    CHECK(file_equals(source, "bad"));
    CHECK(file_equals(destination, "competitor"));
    CHECK_INT(quarantine_temp_count(scratch), 0);
    apk_test_set_quarantine_after_publish_hook(0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_crash_never_leaves_empty_destination) {
    char scratch[128];
    char source[160];
    char destination[176];
    int ready[2];
    int proceed[2];
    pid_t pid;
    int status;

    make_scratch(scratch, sizeof(scratch), "crash");
    sprintf(source, "%s/bad.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(source, "bad");
    CHECK_INT(pipe(ready), 0);
    CHECK_INT(pipe(proceed), 0);
    quarantine_ready_fd = ready[1];
    quarantine_continue_fd = proceed[0];
    apk_test_set_quarantine_hook(quarantine_barrier);
    pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        close(ready[0]);
        close(proceed[1]);
        _exit(apk_quarantine(source) == 0 ? 0 : 1);
    }
    close(ready[1]);
    close(proceed[0]);
    {
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
    }
    close(ready[0]);
    CHECK(file_equals(source, "bad"));
    CHECK(file_equals(destination, "bad"));
    kill(pid, SIGKILL);
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(status != 0);
    CHECK(file_equals(source, "bad"));
    CHECK(file_equals(destination, "bad"));
    close(proceed[1]);
    apk_test_set_quarantine_hook(0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_quarantine_symlink_preserves_target) {
    char scratch[128];
    char target[160];
    char source[160];
    char destination[176];
    char expected[352];
    struct stat st;

    make_scratch(scratch, sizeof(scratch), "symlink");
    sprintf(target, "%s/target.apk", scratch);
    sprintf(source, "%s/link.apk", scratch);
    sprintf(destination, "%s.invalid", source);
    write_text(target, "target-data");
    CHECK_INT(symlink(target, source), 0);
    CHECK_INT(apk_quarantine(source), 0);
    CHECK(lstat(source, &st) != 0 && errno == ENOENT);
    CHECK(file_equals(target, "target-data"));
    CHECK(lstat(destination, &st) == 0 && S_ISREG(st.st_mode));
    sprintf(expected, "symlink -> %s\n", target);
    CHECK(file_equals(destination, expected));

    /* A pre-existing quarantine record is a competitor, not a permanent
       blocker: preserve it while removing only the newly recreated link. */
    CHECK_INT(symlink(target, source), 0);
    write_text(destination, "competitor");
    CHECK_INT(apk_quarantine(source), 0);
    CHECK(lstat(source, &st) != 0 && errno == ENOENT);
    CHECK(file_equals(destination, "competitor"));
    CHECK(file_equals(target, "target-data"));
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void arch_word(unsigned char *p, unsigned long v) {
    int i; for(i=0;i<4;i++) p[3-i]=(unsigned char)(v>>(i*8));
}
/* Without a toolchain profile the default extractor has to cope with a
   symlink stored ahead of its target (file-cmds ships usr/bin/cpio ->
   ../../bin/pax). Rhapsody's /usr/bin/tar is pax's tar personality, which
   chowns through the not-yet-extracted link and exits nonzero. */
TEST(test_default_extractor_handles_forward_symlink) {
    char scratch[160], apk[192], root[192], link[224], real[224];
    unsigned char code[28];
    struct stat st;
    TarEntry entries[] = {
        { ".PKGINFO", '0', 0,
          "pkgname = code\npkgver = 1\narch = i386-apple-rhapsody\n", 0 },
        { "usr/bin/link", '2', "real", "", 0 },
        { "usr/bin/real", '0', 0, 0, 0 }
    };

    make_scratch(scratch, sizeof(scratch), "fwdlink");
    sprintf(apk, "%s/test-i386.apk", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(link, "%s/usr/bin/link", root);
    sprintf(real, "%s/usr/bin/real", root);
    memset(code, 0, sizeof(code));
    arch_word(code, 0xfeedfaceUL); arch_word(code + 4, 7);
    arch_word(code + 12, 1);
    entries[2].data = (char *)code;
    entries[2].binary_size = sizeof(code);
    CHECK_INT(make_apk(apk, entries, 3), 0);
    CHECK_INT(apk_use_arch(apk, root, 0, "code", "1", 1, 0, 0), 0);
    CHECK_INT(lstat(link, &st), 0);
    CHECK(S_ISLNK(st.st_mode));
    CHECK_INT(lstat(real, &st), 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_architecture_use) {
    char scratch[160], apk[192], root[192], marker[224];
    unsigned char code[104];
    TarEntry e[2];
    make_scratch(scratch,sizeof(scratch),"arches");
    sprintf(root,"%s/root",scratch);
    sprintf(marker,"%s/tool",root);
    memset(e,0,sizeof(e)); e[0].name=".PKGINFO"; e[0].type='0';
    e[1].name="tool"; e[1].type='0'; e[1].data=(char*)code; e[1].binary_size=28;
    memset(code,0,sizeof(code)); arch_word(code,0xfeedfaceUL); arch_word(code+4,7); arch_word(code+12,1);
    sprintf(apk,"%s/test-universal.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = universal-apple-rhapsody\n";
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK(apk_use_arch(apk,root,0,"code","1",3,0,0)!=0);
    CHECK(apk_use_arch(apk,root,0,"code",0,1,0,1)!=0);
    CHECK(!file_exists(root)); CHECK(!file_exists(marker));
    sprintf(apk,"%s/test-i386.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = i386\n";
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK_INT(apk_use_arch(apk,0,0,"code",0,1,0,1),0);
    CHECK(apk_use_arch(apk,0,0,"code","1",1,0,0)!=0);
    CHECK(apk_use_arch(apk,root,0,"code",0,3,0,1)!=0);
    sprintf(apk,"%s/test-ppc.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = ppc-apple-rhapsody\n";
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK(apk_use_arch(apk,root,0,"code","1",2,0,0)!=0);
    memset(code,0,sizeof(code)); arch_word(code,0xcafebabeUL); arch_word(code+4,2);
    arch_word(code+8,7); arch_word(code+16,48); arch_word(code+20,28);
    arch_word(code+28,18); arch_word(code+36,76); arch_word(code+40,28);
    arch_word(code+48,0xfeedfaceUL); arch_word(code+52,7); arch_word(code+60,1);
    arch_word(code+76,0xfeedfaceUL); arch_word(code+80,18); arch_word(code+88,1);
    e[1].binary_size=104;
    sprintf(apk,"%s/test-universal.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = universal-apple-rhapsody\n";
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK_INT(apk_use_arch(apk,0,0,"code","1",3,0,0),0);
    CHECK(!file_exists(root));
    CHECK(apk_use_arch(apk,0,0,"wrong","1",3,0,0)!=0);
    CHECK(apk_use_arch(apk,0,0,"code","2",3,0,0)!=0);
    CHECK_INT(apk_use_arch(apk,root,0,"code",0,1,0,1),0);
    CHECK(file_exists(marker));
    sprintf(apk,"%s/test-ppc.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = universal-apple-rhapsody\n";
    e[1].binary_size=104;
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK(apk_use_arch(apk,0,0,"code","1",3,0,0)!=0);
    e[1].binary_size=0; e[1].data="header data";
    sprintf(apk,"%s/test-i386.apk",scratch);
    e[0].data="pkgname = code\npkgver = 1\narch = i386\n";
    CHECK_INT(make_apk(apk,e,2),0);
    CHECK_INT(apk_use_arch(apk,0,0,"code",0,3,0,1),0);
    e[0].data="pkgname = code\npkgver = 1\narch = \n";
    CHECK_INT(make_apk(apk,e,2),0); CHECK(apk_use_arch(apk,0,0,"code",0,3,0,1)!=0);
    e[0].data="pkgname = code\npkgver = 1\narch = m68k\n";
    CHECK_INT(make_apk(apk,e,2),0); CHECK(apk_use_arch(apk,0,0,"code",0,3,0,1)!=0);
    { char command[256]; sprintf(command,"rm -rf %s",scratch); system(command); }
}

/* Vendored upstream tarballs are not APKs: an old-GNU header, which
   apk_validate rejects (test_rejects_oldgnu_header_layout), must extract. */
TEST(test_untar_extracts_oldgnu_upstream_archive) {
    char scratch[128];
    char archive[192];
    char root[192];
    char extracted[256];
    Toolchain tc;
    TarEntry entries[] = {
        { "widget-1.0/hello.txt", '0', 0, "orig\n", ENTRY_OLDGNU }
    };

    make_scratch(scratch, sizeof(scratch), "untar");
    sprintf(archive, "%s/widget-1.0.tar.gz", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(extracted, "%s/widget-1.0/hello.txt", root);
    CHECK_INT(make_apk(archive, entries, 1), 0);
    CHECK_INT(mkdir(root, 0700), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_untar(archive, root, &tc), 0);
    CHECK(access(extracted, F_OK) == 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_untar_missing_archive_fails) {
    Toolchain tc;
    init_toolchain(&tc);
    CHECK_INT(apk_untar("/tmp/rbuild-no-such-archive.tar.gz", "/tmp", &tc), 1);
}

TEST(test_untar_dry_run_touches_nothing) {
    char scratch[128];
    char root[192];
    char archive[192];

    make_scratch(scratch, sizeof(scratch), "untardry");
    sprintf(root, "%s/root", scratch);
    sprintf(archive, "%s/none.tar.gz", scratch);
    exec_dry_run = 1;
    /* root does not exist and the archive is missing: dry-run still only prints */
    CHECK_INT(apk_untar(archive, root, 0), 0);
    exec_dry_run = 0;
    CHECK(access(root, F_OK) != 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void check_untar(const char *path, Toolchain *tc, TarEntry *entries,
                        size_t count, int want) {
    CHECK_INT(make_apk(path, entries, count), 0);
    CHECK_INT(apk_untar_check(path, tc), want);
}

#define LONG_MEMBER "widget-1.0/" \
    "0123456789012345678901234567890123456789" \
    "0123456789012345678901234567890123456789" \
    "0123456789012345678901234567890123456789/file.txt"

TEST(test_untar_check_accepts_safe_archives) {
    char scratch[128];
    char archive[192];
    Toolchain tc;
    TarEntry normal[] = {
        { "widget-1.0/", '5', 0, "", 0 },
        { "widget-1.0/hello.txt", '0', 0, "hi\n", 0 }
    };
    TarEntry oldgnu[] = {
        { "./widget-1.0/hello.txt", '0', 0, "hi\n", ENTRY_OLDGNU }
    };
    TarEntry in_tree_symlink[] = {
        { "widget-1.0/include/b", '0', 0, "b\n", 0 },
        { "widget-1.0/lib/a", '2', "../include/b", "", 0 }
    };
    TarEntry symlink_to_symlink[] = {
        { "lib/cur", '2', "v1", "", 0 },
        { "lib/alias", '2', "cur", "", 0 }
    };
    TarEntry v7[] = {
        { "widget-1.0/", '\0', 0, "", ENTRY_V7 },
        { "widget-1.0/hello.txt", '\0', 0, "hi\n", ENTRY_V7 }
    };

    TarEntry regular_slash_empty[] = {
        { "widget-1.0/d/", '0', 0, "", 0 }
    };

    make_scratch(scratch, sizeof(scratch), "untarcheck");
    sprintf(archive, "%s/widget-1.0.tar.gz", scratch);
    init_toolchain(&tc);
    check_untar(archive, &tc, normal, 2, 0);
    check_untar(archive, &tc, oldgnu, 1, 0);
    check_untar(archive, &tc, in_tree_symlink, 2, 0);
    check_untar(archive, &tc, symlink_to_symlink, 2, 0);
    check_untar(archive, &tc, v7, 2, 0);
    check_untar(archive, &tc, regular_slash_empty, 1, 0);
    /* NULL toolchain: gzip from PATH */
    CHECK_INT(apk_untar_check(archive, 0), 0);
    exec_dry_run = 1;
    CHECK_INT(apk_untar_check("/tmp/rbuild-no-such-archive.tar.gz", &tc), 0);
    exec_dry_run = 0;
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_untar_check_rejects_unsafe_members) {
    char scratch[128];
    char archive[192];
    Toolchain tc;
    TarEntry absolute[] = {
        { "/etc/evil", '0', 0, "evil", 0 }
    };
    TarEntry dotdot[] = {
        { "widget-1.0/../../evil", '0', 0, "evil", 0 }
    };
    TarEntry through_symlink[] = {
        { "widget-1.0/link", '2', "sub", "", 0 },
        { "widget-1.0/./link/evil", '0', 0, "evil", 0 }
    };
    TarEntry escaping_symlink[] = {
        { "a", '2', "../../x", "", 0 }
    };
    TarEntry absolute_hardlink[] = {
        { "widget-1.0/h", '1', "/etc/passwd", "", 0 }
    };
    TarEntry chained_symlink[] = {
        { "a/b/s", '2', "../..", "", 0 },
        { "a/b/l", '2', "s/..", "", 0 }
    };
    TarEntry hardlink_through_symlink[] = {
        { "s", '2', "x", "", 0 },
        { "h", '1', "s/y", "", 0 }
    };
    TarEntry pax_header[] = {
        { "PaxHeaders/widget-1.0", 'x', 0, "20 path=widget-1.0\n", 0 },
        { "widget-1.0", '0', 0, "x", 0 }
    };
    TarEntry gnu_long_name[] = {
        { "././@LongLink", 'L', 0, "widget-1.0/long", ENTRY_OLDGNU },
        { "widget-1.0/long", '0', 0, "x", ENTRY_OLDGNU }
    };
    TarEntry gnu_long_link[] = {
        { "././@LongLink", 'K', 0, "long-target", ENTRY_OLDGNU },
        { "widget-1.0/l", '2', "t", "", ENTRY_OLDGNU }
    };
    TarEntry ustar_prefix[] = {
        { "../up/evil", '0', 0, "x", ENTRY_PREFIX }
    };
    /* now refused as a prefix without POSIX magic, before the '..' check */
    TarEntry oldgnu_prefix[] = {
        { "../up/evil", '0', 0, "x", ENTRY_OLDGNU | ENTRY_PREFIX }
    };
    TarEntry empty_name[] = {
        { "", '0', 0, "x", 0 }
    };
    TarEntry mixed_format[] = {
        { "widget-1.0/a", '0', 0, "a", 0 },
        { "widget-1.0/b", '0', 0, "b", ENTRY_V7 }
    };
    TarEntry nul_size[] = {
        { "widget-1.0/f", '0', 0, "x", ENTRY_NUL_SIZE }
    };
    TarEntry unterminated_name[] = {
        { LONG_MEMBER, '0', 0, "x", 0 }
    };
    TarEntry unterminated_link[] = {
        { "widget-1.0/l", '2', LONG_MEMBER, "", 0 }
    };
    TarEntry symlink_with_data[] = {
        { "widget-1.0/l", '2', "x", "abc", 0 }
    };
    TarEntry later_symlink[] = {
        { "a/l", '2', "b/..", "", 0 },
        { "a/b", '2', "..", "", 0 }
    };
    TarEntry leading_zeros[] = {
        { "widget-1.0/f", '0', 0, "x", ENTRY_LEADING_ZEROS }
    };
    TarEntry bad_checksum[] = {
        { "widget-1.0/f", '0', 0, "x", ENTRY_BAD_CHECKSUM }
    };
    TarEntry truncated[] = {
        { "widget-1.0/f", '0', 0, "short", ENTRY_TRUNCATED }
    };
    /* on a case-folding filesystem pkg/l is the symlink pkg/L */
    TarEntry case_folded_symlinks[] = {
        { "pkg/L", '2', "..", "", 0 },
        { "pkg/l/M", '2', "..", "", 0 },
        { "pkg/l/m/N", '2', "..", "", 0 },
        { "pkg/l/m/n/evil", '0', 0, "x", 0 }
    };
    TarEntry unsupported_type[] = {
        { "widget-1.0/v", 'V', 0, "", 0 }
    };
    TarEntry oldgnu_safe_prefix[] = {
        { "widget-1.0/f", '0', 0, "x", ENTRY_OLDGNU | ENTRY_PREFIX }
    };
    /* pax skips no data for a directory; GNU tar would skip the next block */
    TarEntry directory_with_size[] = {
        { "widget-1.0/", '5', 0, 0, 0, 512 }
    };
    /* ASCII case folding cannot match HFS+ Unicode folding */
    TarEntry non_ascii_name[] = {
        { "widget-1.0/caf\351", '0', 0, "x", 0 }
    };
    TarEntry regular_slash_with_data[] = {
        { "widget-1.0/d/", '0', 0, "x", 0 }
    };
    TarEntry inner[] = {
        { "widget-1.0/g", '0', 0, "", 0 }
    };
    char inner_header[512];
    char inner_path[192];
    FILE *fp;

    make_scratch(scratch, sizeof(scratch), "untarunsafe");
    sprintf(archive, "%s/evil.tar.gz", scratch);
    sprintf(inner_path, "%s/inner.tar", scratch);
    CHECK_INT(write_tar(inner_path, inner, 1), 0);
    fp = fopen(inner_path, "rb");
    CHECK(fp != 0);
    if (fp == 0) return;
    CHECK(fread(inner_header, 1, sizeof(inner_header), fp) ==
          sizeof(inner_header));
    fclose(fp);
    directory_with_size[0].data = inner_header;
    init_toolchain(&tc);
    check_untar(archive, &tc, absolute, 1, 1);
    check_untar(archive, &tc, dotdot, 1, 1);
    check_untar(archive, &tc, through_symlink, 2, 1);
    check_untar(archive, &tc, escaping_symlink, 1, 1);
    check_untar(archive, &tc, absolute_hardlink, 1, 1);
    check_untar(archive, &tc, chained_symlink, 2, 1);
    check_untar(archive, &tc, hardlink_through_symlink, 2, 1);
    check_untar(archive, &tc, pax_header, 2, 1);
    check_untar(archive, &tc, gnu_long_name, 2, 1);
    check_untar(archive, &tc, gnu_long_link, 2, 1);
    check_untar(archive, &tc, ustar_prefix, 1, 1);
    check_untar(archive, &tc, oldgnu_prefix, 1, 1);
    check_untar(archive, &tc, empty_name, 1, 1);
    check_untar(archive, &tc, mixed_format, 2, 1);
    check_untar(archive, &tc, nul_size, 1, 1);
    check_untar(archive, &tc, unterminated_name, 1, 1);
    check_untar(archive, &tc, unterminated_link, 1, 1);
    check_untar(archive, &tc, symlink_with_data, 1, 1);
    check_untar(archive, &tc, later_symlink, 2, 1);
    check_untar(archive, &tc, leading_zeros, 1, 1);
    check_untar(archive, &tc, bad_checksum, 1, 1);
    check_untar(archive, &tc, truncated, 1, 1);
    check_untar(archive, &tc, case_folded_symlinks, 4, 1);
    check_untar(archive, &tc, unsupported_type, 1, 1);
    check_untar(archive, &tc, oldgnu_safe_prefix, 1, 1);
    check_untar(archive, &tc, directory_with_size, 1, 1);
    check_untar(archive, &tc, regular_slash_with_data, 1, 1);
    check_untar(archive, &tc, non_ascii_name, 1, 1);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

static void run_all(void) {
    RUN(test_architecture_use);
    RUN(test_default_extractor_handles_forward_symlink);
    RUN(test_validate_extract_and_quarantine);
    RUN(test_configured_tools_are_used_without_tar_z);
    RUN(test_validation_rejects_unsafe_or_malformed_members);
    RUN(test_metadata_spelling_variants_are_accepted);
    RUN(test_rejects_oldgnu_header_layout);
    RUN(test_accepts_character_device_member);
    RUN(test_extract_preserves_hard_links);
    RUN(test_implicit_directories_preserve_existing_metadata);
    RUN(test_explicit_directory_metadata_is_applied);
    RUN(test_readdir_error_fails_merge);
    RUN(test_extract_rejects_preexisting_root_symlink);
    RUN(test_extract_rejects_unvalidated_archive);
    RUN(test_validate_with_closed_standard_fds);
    RUN(test_extract_checks_both_pipeline_statuses);
    RUN(test_extract_rejects_changed_artifact);
    RUN(test_extract_does_not_reopen_validated_path);
    RUN(test_extract_uses_immutable_private_copy);
    RUN(test_quarantine_source_replacement_is_preserved);
    RUN(test_quarantine_pre_link_source_replacement_rolls_back_destination);
    RUN(test_quarantine_replaced_destination_is_not_overwritten);
    RUN(test_quarantine_immediate_publish_replacement_is_preserved);
    RUN(test_quarantine_crash_never_leaves_empty_destination);
    RUN(test_quarantine_symlink_preserves_target);
    RUN(test_untar_extracts_oldgnu_upstream_archive);
    RUN(test_untar_missing_archive_fails);
    RUN(test_untar_dry_run_touches_nothing);
    RUN(test_untar_check_accepts_safe_archives);
    RUN(test_untar_check_rejects_unsafe_members);
}

TEST_MAIN()
