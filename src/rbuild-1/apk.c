#include "apk.h"
#include "architecture.h"
#include "products.h"
#include "exec.h"
#include "strutil.h"

#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <utime.h>
#include <unistd.h>

#define TAR_BLOCK_SIZE 512

#ifdef RBUILD_APK_TESTING
static void (*apk_quarantine_test_hook)(void) = 0;
static void (*apk_quarantine_pre_link_test_hook)(void) = 0;
static void (*apk_quarantine_after_publish_test_hook)(void) = 0;
static int apk_readdir_calls_before_failure = -1;

void apk_test_set_quarantine_hook(void (*hook)(void)) {
    apk_quarantine_test_hook = hook;
}

void apk_test_set_quarantine_pre_link_hook(void (*hook)(void)) {
    apk_quarantine_pre_link_test_hook = hook;
}

void apk_test_set_quarantine_after_publish_hook(void (*hook)(void)) {
    apk_quarantine_after_publish_test_hook = hook;
}

void apk_test_set_readdir_failure(int calls_before_failure) {
    apk_readdir_calls_before_failure = calls_before_failure;
}

static void run_quarantine_test_hook(void) {
    if (apk_quarantine_test_hook != 0) apk_quarantine_test_hook();
}

static void run_quarantine_pre_link_test_hook(void) {
    if (apk_quarantine_pre_link_test_hook != 0)
        apk_quarantine_pre_link_test_hook();
}

static void run_quarantine_after_publish_test_hook(void) {
    if (apk_quarantine_after_publish_test_hook != 0)
        apk_quarantine_after_publish_test_hook();
}

static struct dirent *read_directory(DIR *dir) {
    if (apk_readdir_calls_before_failure == 0) {
        errno = EIO;
        return 0;
    }
    if (apk_readdir_calls_before_failure > 0)
        apk_readdir_calls_before_failure--;
    return readdir(dir);
}
#else
static void run_quarantine_test_hook(void) {
}
static void run_quarantine_pre_link_test_hook(void) {
}
static void run_quarantine_after_publish_test_hook(void) {
}
static struct dirent *read_directory(DIR *dir) {
    return readdir(dir);
}
#endif

/* Extractor used when no toolchain profile names a tar. Rhapsody's tar is
   pax's tar personality, which chowns through symlinks and so exits nonzero
   on any archive whose symlink precedes its target (file-cmds ships
   usr/bin/cpio -> ../../bin/pax). Ask for pax by name instead -- resolved on
   PATH, like the tar it replaces -- and drive it the way the profile's
   pax-gnutar.sh wrapper does. */
#define FALLBACK_TAR "pax"

static int tar_is_pax(const Toolchain *tc) {
    return strcmp(tc->tar, FALLBACK_TAR) == 0;
}

static int valid_tools(const Toolchain *tc) {
    return tc != 0 && tc->tar != 0 && tc->tar[0] != '\0' &&
           tc->gzip != 0 && tc->gzip[0] != '\0';
}

static int child_succeeded(int status) {
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int wait_child(pid_t pid) {
    int status;

    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return 1;
    }
    return child_succeeded(status) ? 0 : 1;
}

static int start_gzip(int artifact_fd, const Toolchain *tc,
                      int *read_fd, pid_t *pid_out) {
    int fds[2];
    pid_t pid;

    if (pipe(fds) != 0) return 1;
    pid = fork();
    if (pid < 0) {
        close(fds[0]);
        if (fds[1] != STDOUT_FILENO) close(fds[1]);
        return 1;
    }
    if (pid == 0) {
        char *argv[3];
        close(fds[0]);
        if (dup2(artifact_fd, STDIN_FILENO) < 0) _exit(127);
        if (dup2(fds[1], STDOUT_FILENO) < 0) _exit(127);
        if (artifact_fd > STDERR_FILENO) close(artifact_fd);
        close(fds[1]);
        argv[0] = tc->gzip;
        argv[1] = "-dc";
        argv[2] = 0;
        execvp(argv[0], argv);
        fprintf(stderr, "rbuild: exec \"%s\" failed\n", argv[0]);
        _exit(127);
    }
    close(fds[1]);
    *read_fd = fds[0];
    *pid_out = pid;
    return 0;
}

static int read_exact(int fd, char *buffer, size_t count) {
    size_t used = 0;

    while (used < count) {
        ssize_t got = read(fd, buffer + used, count - used);
        if (got == 0) return used == 0 ? 0 : -1;
        if (got < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        used += (size_t)got;
    }
    return 1;
}

static int skip_exact(int fd, unsigned long count) {
    char buffer[4096];

    while (count != 0) {
        size_t chunk = count > sizeof(buffer) ? sizeof(buffer) : (size_t)count;
        int result = read_exact(fd, buffer, chunk);
        if (result != 1) return 1;
        count -= (unsigned long)chunk;
    }
    return 0;
}

static int block_is_zero(const char *block) {
    size_t i;
    for (i = 0; i < TAR_BLOCK_SIZE; i++)
        if (block[i] != '\0') return 0;
    return 1;
}

static int parse_octal(const char *field, size_t width,
                       unsigned long *value_out) {
    size_t i = 0;
    unsigned long value = 0;
    int saw_digit = 0;

    while (i < width && (field[i] == ' ' || field[i] == '\0')) i++;
    for (; i < width && field[i] >= '0' && field[i] <= '7'; i++) {
        unsigned long digit = (unsigned long)(field[i] - '0');
        unsigned long next;
        saw_digit = 1;
        if (value > (ULONG_MAX - digit) / 8) return 1;
        next = value * 8 + digit;
        value = next;
    }
    while (i < width && (field[i] == ' ' || field[i] == '\0')) i++;
    if (!saw_digit || i != width) return 1;
    *value_out = value;
    return 0;
}

static int valid_checksum(const char *header) {
    unsigned long stored;
    unsigned long sum = 0;
    size_t i;

    if (parse_octal(header + 148, 8, &stored) != 0) return 0;
    for (i = 0; i < TAR_BLOCK_SIZE; i++) {
        if (i >= 148 && i < 156) sum += (unsigned char)' ';
        else sum += (unsigned char)header[i];
    }
    return sum == stored;
}

static void field_string(const char *field, size_t width, char *out) {
    size_t length = 0;
    while (length < width && field[length] != '\0') length++;
    memcpy(out, field, length);
    out[length] = '\0';
}

static int header_name(const char *header, char *name, size_t capacity) {
    char base[101];
    char prefix[156];
    size_t needed;

    field_string(header, 100, base);
    field_string(header + 345, 155, prefix);
    needed = strlen(base) + strlen(prefix) + 2;
    if (needed > capacity || base[0] == '\0') return 1;
    if (prefix[0] != '\0') sprintf(name, "%s/%s", prefix, base);
    else strcpy(name, base);
    return 0;
}

static int normalize_name(const char *input, char *output, size_t capacity) {
    const char *p;
    size_t used = 0;

    if (input[0] == '/') return 1;
    p = input;
    while (*p != '\0') {
        const char *start;
        size_t length;
        while (*p == '/') p++;
        if (*p == '\0') break;
        start = p;
        while (*p != '\0' && *p != '/') p++;
        length = (size_t)(p - start);
        if (length == 1 && start[0] == '.') continue;
        if (length == 2 && start[0] == '.' && start[1] == '.') return 1;
        if (used != 0) {
            if (used + 1 >= capacity) return 1;
            output[used++] = '/';
        }
        if (used + length >= capacity) return 1;
        memcpy(output + used, start, length);
        used += length;
    }
    output[used] = '\0';
    return 0;
}

static int component_count(const char *path) {
    int count = 0;
    const char *p = path;
    while (*p != '\0') {
        count++;
        while (*p != '\0' && *p != '/') p++;
        if (*p == '/') p++;
    }
    return count;
}

static int link_target_safe(const char *member, const char *target,
                            int hardlink) {
    const char *p;
    int depth;

    if (target[0] == '/') return 0;
    depth = hardlink ? 0 : component_count(member) - 1;
    p = target;
    while (*p != '\0') {
        const char *start;
        size_t length;
        while (*p == '/') p++;
        if (*p == '\0') break;
        start = p;
        while (*p != '\0' && *p != '/') p++;
        length = (size_t)(p - start);
        if (length == 1 && start[0] == '.') continue;
        if (length == 2 && start[0] == '.' && start[1] == '.') {
            depth--;
            if (depth < 0) return 0;
        } else {
            depth++;
        }
    }
    return 1;
}

static int descends_through_symlink(const char *name,
                                    const strlist *symlinks) {
    size_t i;
    for (i = 0; i < symlinks->count; i++) {
        size_t length = strlen(symlinks->items[i]);
        if (strncmp(name, symlinks->items[i], length) == 0 &&
            name[length] == '/') return 1;
    }
    return 0;
}

typedef struct {
    char *pkgname;
    char *pkgver;
    char *architecture;
} ApkIdentity;

static void identity_free(ApkIdentity *identity) {
    free(identity->pkgname); free(identity->pkgver); free(identity->architecture);
    memset(identity, 0, sizeof(*identity));
}

static int parse_identity(char *data, ApkIdentity *identity) {
    char *line = data;
    while (line != 0 && *line != '\0') {
        char *next = strchr(line, '\n');
        char *equals;
        char *key;
        char *value;
        char **slot = 0;
        if (next != 0) *next++ = '\0';
        line = str_trim(line);
        if (*line == '\0') { line = next; continue; }
        equals = strchr(line, '=');
        if (equals == 0) { line = next; continue; }
        *equals = '\0';
        key = str_trim(line); value = str_trim(equals + 1);
        if (strcmp(key, "pkgname") == 0) slot = &identity->pkgname;
        else if (strcmp(key, "pkgver") == 0) slot = &identity->pkgver;
        else if (strcmp(key, "arch") == 0) slot = &identity->architecture;
        if (slot != 0) {
            if (*slot != 0 || *value == '\0') return 1;
            *slot = xstrdup(value);
        }
        line = next;
    }
    return identity->pkgname == 0 || identity->pkgver == 0 ||
           identity->architecture == 0;
}

static int validate_tar_stream(int fd, strlist *explicit_dirs,
                               ApkIdentity *identity) {
    char header[TAR_BLOCK_SIZE];
    strlist symlinks;
    int zero_blocks = 0;
    int metadata_count = 0;
    int result = 1;

    strlist_init(&symlinks);
    for (;;) {
        int read_result = read_exact(fd, header, sizeof(header));
        unsigned long size;
        unsigned long padding;
        char raw_name[258];
        char name[258];
        char linkname[101];
        char type;
        int consumed = 0;

        if (read_result != 1) break;
        if (block_is_zero(header)) {
            zero_blocks++;
            if (zero_blocks == 2) {
                char trailing[512];
                int trailing_result;
                result = 0;
                while ((trailing_result = read_exact(fd, trailing,
                                                     sizeof(trailing))) == 1) {
                    if (!block_is_zero(trailing)) result = 1;
                }
                if (trailing_result < 0) result = 1;
                break;
            }
            continue;
        }
        if (zero_blocks != 0 || !valid_checksum(header) ||
            memcmp(header + 257, "ustar\0", 6) != 0 ||
            memcmp(header + 263, "00", 2) != 0 ||
            parse_octal(header + 124, 12, &size) != 0 ||
            header_name(header, raw_name, sizeof(raw_name)) != 0 ||
            normalize_name(raw_name, name, sizeof(name)) != 0 ||
            descends_through_symlink(name, &symlinks))
            break;

        type = header[156];
        if (type != '\0' && type != '0' && type != '1' && type != '2' &&
            type != '3' && type != '4' && type != '5') break;
        if (name[0] == '\0' && type != '5') break;
        field_string(header + 157, 100, linkname);
        if ((type == '3' || type == '4') &&
            (size != 0 || linkname[0] != '\0')) break;
        if (type == '3' || type == '4') {
            unsigned long device_major;
            unsigned long device_minor;
            if (parse_octal(header + 329, 8, &device_major) != 0 ||
                parse_octal(header + 337, 8, &device_minor) != 0) break;
        }
        if ((type == '1' || type == '2') &&
            !link_target_safe(name, linkname, type == '1')) break;
        if (type == '2') strlist_push(&symlinks, name);
        if (type == '5' && name[0] != '\0' && explicit_dirs != 0)
            strlist_push(explicit_dirs, name);
        if (strcmp(name, ".PKGINFO") == 0) {
            metadata_count++;
            if ((type != '\0' && type != '0') || metadata_count != 1) break;
            if (identity != 0) {
                char *metadata;
                if (size > 16384UL) break;
                metadata = (char *)malloc((size_t)size + 1);
                if (metadata == 0) break;
                if (read_exact(fd, metadata, (size_t)size) != 1) {
                    free(metadata); break;
                }
                metadata[size] = '\0';
                consumed = 1;
                if (parse_identity(metadata, identity) != 0) {
                    free(metadata); break;
                }
                free(metadata);
            }
        }

        if (!consumed && skip_exact(fd, size) != 0) break;
        padding = (TAR_BLOCK_SIZE - (size % TAR_BLOCK_SIZE)) % TAR_BLOCK_SIZE;
        if (skip_exact(fd, padding) != 0) break;
    }
    if (result == 0 && metadata_count != 1) result = 1;
    strlist_free(&symlinks);
    return result;
}

static int tar_pipeline(int artifact_fd, const char *root, int list_only,
                        const Toolchain *tc);
static int same_artifact(const struct stat *a, const struct stat *b);

static int validate_artifact(int artifact_fd, const Toolchain *tc,
                             strlist *explicit_dirs, ApkIdentity *identity) {
    int stream_fd;
    pid_t gzip_pid;
    int parse_result;
    int gzip_result;
    struct stat before;
    struct stat after;

    if (fstat(artifact_fd, &before) != 0 || !S_ISREG(before.st_mode)) return 1;
    if (lseek(artifact_fd, 0, SEEK_SET) < 0) return 1;
    if (start_gzip(artifact_fd, tc, &stream_fd, &gzip_pid) != 0) return 1;
    parse_result = validate_tar_stream(stream_fd, explicit_dirs, identity);
    close(stream_fd);
    gzip_result = wait_child(gzip_pid);
    if (parse_result != 0 || gzip_result != 0) return 1;
    if (tar_pipeline(artifact_fd, 0, 1, tc) != 0) return 1;
    if (fstat(artifact_fd, &after) != 0 ||
        !same_artifact(&before, &after)) return 1;
    return 0;
}

static int same_artifact(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
           a->st_size == b->st_size && a->st_mtime == b->st_mtime;
}

static int tar_pipeline(int artifact_fd, const char *root, int list_only,
                        const Toolchain *tc) {
    int fds[2];
    pid_t gzip_pid;
    pid_t tar_pid;
    int gzip_result;
    int tar_result;

    if (lseek(artifact_fd, 0, SEEK_SET) < 0) return 1;
    if (pipe(fds) != 0) return 1;
    gzip_pid = fork();
    if (gzip_pid < 0) {
        if (fds[0] != STDIN_FILENO) close(fds[0]);
        close(fds[1]);
        return 1;
    }
    if (gzip_pid == 0) {
        char *argv[3];
        close(fds[0]);
        if (dup2(artifact_fd, STDIN_FILENO) < 0) _exit(127);
        if (dup2(fds[1], STDOUT_FILENO) < 0) _exit(127);
        if (artifact_fd > STDERR_FILENO) close(artifact_fd);
        close(fds[1]);
        argv[0] = tc->gzip;
        argv[1] = "-dc";
        argv[2] = 0;
        execvp(argv[0], argv);
        _exit(127);
    }
    tar_pid = fork();
    if (tar_pid < 0) {
        close(fds[0]);
        close(fds[1]);
        wait_child(gzip_pid);
        return 1;
    }
    if (tar_pid == 0) {
        char *argv[7];
        close(fds[1]);
        if (artifact_fd > STDERR_FILENO) close(artifact_fd);
        if (dup2(fds[0], STDIN_FILENO) < 0) _exit(127);
        close(fds[0]);
        argv[0] = tc->tar;
        if (list_only) {
            int null_fd = open("/dev/null", O_WRONLY);
            if (null_fd < 0 || dup2(null_fd, STDOUT_FILENO) < 0) _exit(127);
            if (null_fd > STDERR_FILENO) close(null_fd);
            if (tar_is_pax(tc)) {
                argv[1] = 0;
            } else {
                argv[1] = "-tf";
                argv[2] = "-";
                argv[3] = 0;
            }
        } else if (tar_is_pax(tc)) {
            if (chdir(root) != 0) _exit(127);
            argv[1] = "-r";
            argv[2] = 0;
        } else {
            argv[1] = "-C";
            argv[2] = (char *)root;
            argv[3] = "-xf";
            argv[4] = "-";
            argv[5] = 0;
        }
        execvp(argv[0], argv);
        _exit(127);
    }
    close(fds[0]);
    close(fds[1]);
    gzip_result = wait_child(gzip_pid);
    tar_result = wait_child(tar_pid);
    return gzip_result != 0 || tar_result != 0;
}

static int make_private_dir(char *path, size_t capacity, const char *tag) {
    int attempt;
    long now = (long)time(0);

    for (attempt = 0; attempt < 100; attempt++) {
        sprintf(path, "/tmp/rbuild-apk-%s-%ld-%ld-%d", tag,
                (long)getpid(), now, attempt);
        if (strlen(path) + 1 > capacity) return 1;
        if (mkdir(path, 0700) == 0) return 0;
        if (errno != EEXIST) return 1;
    }
    return 1;
}

static int remove_private_dir(const char *path) {
    char *argv[4];
    argv[0] = "/bin/rm";
    argv[1] = "-rf";
    argv[2] = (char *)path;
    argv[3] = 0;
    return exec_run_checked(argv);
}

static int copy_bytes(int source_fd, int destination_fd) {
    char buffer[16384];
    ssize_t count;

    if (lseek(source_fd, 0, SEEK_SET) < 0) return 1;
    while ((count = read(source_fd, buffer, sizeof(buffer))) != 0) {
        ssize_t written = 0;
        if (count < 0) {
            if (errno == EINTR) continue;
            return 1;
        }
        while (written < count) {
            ssize_t result = write(destination_fd, buffer + written,
                                   (size_t)(count - written));
            if (result <= 0) {
                if (result < 0 && errno == EINTR) continue;
                return 1;
            }
            written += result;
        }
    }
    if (fsync(destination_fd) != 0 || lseek(destination_fd, 0, SEEK_SET) < 0)
        return 1;
    return 0;
}

static int make_immutable_copy(const char *path, const char *private_dir,
                               int *copy_fd, struct stat *source_stat) {
    char copy_path[256];
    int source_fd;
    int destination_fd;
    int immutable_fd;
    struct stat entry;
    struct stat current;

    if (strlen(private_dir) + sizeof("/archive.apk") > sizeof(copy_path))
        return 1;
    sprintf(copy_path, "%s/archive.apk", private_dir);
    if (lstat(path, &entry) != 0 || !S_ISREG(entry.st_mode)) return 1;
    source_fd = open(path, O_RDONLY);
    if (source_fd < 0) return 1;
    if (fstat(source_fd, source_stat) != 0 ||
        !S_ISREG(source_stat->st_mode) ||
        !same_artifact(&entry, source_stat)) {
        close(source_fd);
        return 1;
    }
    destination_fd = open(copy_path, O_RDWR | O_CREAT | O_EXCL, 0400);
    if (destination_fd < 0) {
        close(source_fd);
        return 1;
    }
    if (copy_bytes(source_fd, destination_fd) != 0 ||
        fchmod(destination_fd, 0400) != 0 ||
        fstat(source_fd, &current) != 0 ||
        !same_artifact(source_stat, &current)) {
        close(source_fd);
        close(destination_fd);
        return 1;
    }
    close(source_fd);
    if (close(destination_fd) != 0) return 1;
    immutable_fd = open(copy_path, O_RDONLY);
    if (immutable_fd < 0) return 1;
    if (unlink(copy_path) != 0) {
        close(immutable_fd);
        return 1;
    }
    *copy_fd = immutable_fd;
    return 0;
}

static int join_path(char *out, size_t capacity, const char *left,
                     const char *right) {
    size_t needed = strlen(left) + strlen(right) + 2;
    if (needed > capacity) return 1;
    if (right[0] == '\0') strcpy(out, left);
    else sprintf(out, "%s/%s", left, right);
    return 0;
}

static int ensure_directory_path(const char *path) {
    char *argv[4];
    struct stat st;

    argv[0] = "/bin/mkdir";
    argv[1] = "-p";
    argv[2] = (char *)path;
    argv[3] = 0;
    if (exec_run_checked(argv) != 0) return 1;
    return lstat(path, &st) != 0 || !S_ISDIR(st.st_mode);
}

static int remove_non_directory(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return errno == ENOENT ? 0 : 1;
    if (S_ISDIR(st.st_mode)) return 1;
    return unlink(path) != 0;
}

static int apply_times(const char *path, const struct stat *st) {
    struct utimbuf times;
    times.actime = st->st_atime;
    times.modtime = st->st_mtime;
    return utime(path, &times) != 0;
}

static int copy_regular(const char *source, const char *destination,
                        const struct stat *st) {
    int source_fd;
    int destination_fd;
    int result = 0;

    if (remove_non_directory(destination) != 0) return 1;
    source_fd = open(source, O_RDONLY);
    if (source_fd < 0) return 1;
    destination_fd = open(destination, O_WRONLY | O_CREAT | O_EXCL,
                          st->st_mode & 07777);
    if (destination_fd < 0) {
        close(source_fd);
        return 1;
    }
    if (copy_bytes(source_fd, destination_fd) != 0 ||
        fchown(destination_fd, st->st_uid, st->st_gid) != 0 ||
        fchmod(destination_fd, st->st_mode & 07777) != 0)
        result = 1;
    close(source_fd);
    if (close(destination_fd) != 0) result = 1;
    if (result == 0 && apply_times(destination, st) != 0) result = 1;
    if (result != 0) unlink(destination);
    return result;
}

typedef struct MergeLink {
    dev_t stage_device;
    ino_t stage_inode;
    char *destination;
    struct MergeLink *next;
} MergeLink;

static MergeLink *find_merge_link(MergeLink *links,
                                  const struct stat *st) {
    while (links != 0) {
        if (links->stage_device == st->st_dev &&
            links->stage_inode == st->st_ino) return links;
        links = links->next;
    }
    return 0;
}

static int remember_merge_link(MergeLink **links, const struct stat *st,
                               const char *destination) {
    MergeLink *link_entry;
    size_t length = strlen(destination) + 1;

    link_entry = (MergeLink *)malloc(sizeof(MergeLink));
    if (link_entry == 0) return 1;
    link_entry->destination = (char *)malloc(length);
    if (link_entry->destination == 0) {
        free(link_entry);
        return 1;
    }
    memcpy(link_entry->destination, destination, length);
    link_entry->stage_device = st->st_dev;
    link_entry->stage_inode = st->st_ino;
    link_entry->next = *links;
    *links = link_entry;
    return 0;
}

static void free_merge_links(MergeLink *links) {
    while (links != 0) {
        MergeLink *next = links->next;
        free(links->destination);
        free(links);
        links = next;
    }
}

static int link_regular(const char *source, const char *destination) {
    struct stat before;
    struct stat source_after;
    struct stat destination_after;
    int destination_exists;

    if (lstat(source, &before) != 0 || !S_ISREG(before.st_mode) ||
        remove_non_directory(destination) != 0 ||
        link(source, destination) != 0) return 1;
    destination_exists = lstat(destination, &destination_after) == 0;
    if (lstat(source, &source_after) == 0 && destination_exists &&
        S_ISREG(source_after.st_mode) &&
        source_after.st_dev == before.st_dev &&
        source_after.st_ino == before.st_ino &&
        destination_after.st_dev == before.st_dev &&
        destination_after.st_ino == before.st_ino) return 0;
    if (destination_exists && destination_after.st_dev == before.st_dev &&
        destination_after.st_ino == before.st_ino) unlink(destination);
    return 1;
}

static int merge_regular(const char *source, const char *destination,
                         const struct stat *st, MergeLink **links) {
    MergeLink *existing;

    if (st->st_nlink <= 1) return copy_regular(source, destination, st);
    existing = find_merge_link(*links, st);
    if (existing != 0)
        return link_regular(existing->destination, destination);
    if (copy_regular(source, destination, st) != 0) return 1;
    if (remember_merge_link(links, st, destination) != 0) {
        unlink(destination);
        return 1;
    }
    return 0;
}

static int string_list_contains(const strlist *list, const char *value) {
    size_t i;
    for (i = 0; i < list->count; i++)
        if (strcmp(list->items[i], value) == 0) return 1;
    return 0;
}

static int merge_entry(const char *stage, const char *root, const char *rel,
                       MergeLink **links, const strlist *explicit_dirs) {
    char source[1024];
    char destination[1024];
    struct stat st;

    if (join_path(source, sizeof(source), stage, rel) != 0 ||
        join_path(destination, sizeof(destination), root, rel) != 0 ||
        lstat(source, &st) != 0) return 1;
    if (S_ISDIR(st.st_mode)) {
        DIR *dir;
        struct dirent *entry;
        struct stat existing;
        int existed = 0;
        if (lstat(destination, &existing) == 0) {
            if (!S_ISDIR(existing.st_mode)) {
                errno = ENOTDIR;
                return 1;
            }
            existed = 1;
        } else if (errno == ENOENT) {
            if (mkdir(destination, st.st_mode & 07777) != 0) return 1;
        } else return 1;
        dir = opendir(source);
        if (dir == 0) return 1;
        for (;;) {
            char child[1024];
            int saved_errno;
            errno = 0;
            entry = read_directory(dir);
            if (entry == 0) {
                saved_errno = errno;
                if (closedir(dir) != 0 && saved_errno == 0)
                    saved_errno = errno;
                if (saved_errno != 0) {
                    errno = saved_errno;
                    return 1;
                }
                break;
            }
            if (strcmp(entry->d_name, ".") == 0 ||
                strcmp(entry->d_name, "..") == 0) continue;
            if (rel[0] == '\0') {
                if (strlen(entry->d_name) >= sizeof(child)) {
                    closedir(dir);
                    return 1;
                }
                strcpy(child, entry->d_name);
            } else if (join_path(child, sizeof(child), rel,
                                 entry->d_name) != 0) {
                closedir(dir);
                return 1;
            }
            if (merge_entry(stage, root, child, links,
                            explicit_dirs) != 0) {
                closedir(dir);
                return 1;
            }
        }
        if (rel[0] != '\0' && string_list_contains(explicit_dirs, rel)) {
            if (chown(destination, st.st_uid, st.st_gid) != 0 ||
                chmod(destination, st.st_mode & 07777) != 0 ||
                apply_times(destination, &st) != 0) return 1;
        } else if (existed && apply_times(destination, &existing) != 0) {
            return 1;
        }
        return 0;
    }
    if (S_ISREG(st.st_mode))
        return merge_regular(source, destination, &st, links);
    if (S_ISLNK(st.st_mode)) {
        char target[1024];
        int length = readlink(source, target, sizeof(target) - 1);
        if (length < 0 || remove_non_directory(destination) != 0) return 1;
        target[length] = '\0';
        /* Rhapsody lacks portable no-follow timestamp/ownership setters;
           preserve the validated link target without following it. */
        return symlink(target, destination) != 0;
    }
    if (S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode)) {
        if (remove_non_directory(destination) != 0 ||
            mknod(destination, st.st_mode, st.st_rdev) != 0 ||
            chown(destination, st.st_uid, st.st_gid) != 0 ||
            chmod(destination, st.st_mode & 07777) != 0 ||
            apply_times(destination, &st) != 0) return 1;
        return 0;
    }
    return 1;
}

static int merge_stage(const char *stage, const char *root,
                       const strlist *explicit_dirs) {
    MergeLink *links = 0;
    int result;

    if (ensure_directory_path(root) != 0) {
        fprintf(stderr, "rbuild: cannot prepare APK root %s: %s\n",
                root, strerror(errno));
        return 1;
    }
    result = merge_entry(stage, root, "", &links, explicit_dirs);
    free_merge_links(links);
    if (result != 0) {
        fprintf(stderr, "rbuild: cannot merge APK stage into %s: %s\n",
                root, strerror(errno));
        return 1;
    }
    return 0;
}

int apk_validate(const char *path, const Toolchain *tc) {
    char private_dir[128];
    int artifact_fd = -1;
    int result;
    struct stat source;
    struct stat current;

    if (path == 0 || path[0] == '\0' || !valid_tools(tc)) return 1;
    if (make_private_dir(private_dir, sizeof(private_dir), "validate") != 0)
        return 1;
    if (make_immutable_copy(path, private_dir, &artifact_fd, &source) != 0) {
        remove_private_dir(private_dir);
        return 1;
    }
    result = validate_artifact(artifact_fd, tc, 0, 0);
    if (result == 0 &&
        (lstat(path, &current) != 0 || !S_ISREG(current.st_mode) ||
         !same_artifact(&source, &current)))
        result = 1;
    close(artifact_fd);
    if (remove_private_dir(private_dir) != 0) result = 1;
    return result;
}

int apk_validate_readonly(const char *path, const Toolchain *tc) {
    int artifact_fd;
    int result;
    if (path == 0 || path[0] == '\0' || !valid_tools(tc)) return 1;
    artifact_fd = open(path, O_RDONLY);
    if (artifact_fd < 0) return 1;
    result = validate_artifact(artifact_fd, tc, 0, 0);
    close(artifact_fd);
    return result;
}

static int identity_matches(const ApkIdentity *identity, const char *pkgname,
                            const char *pkgver, const char *architecture) {
    return identity->pkgname != 0 && identity->pkgver != 0 &&
           identity->architecture != 0 &&
           strcmp(identity->pkgname, pkgname) == 0 &&
           strcmp(identity->pkgver, pkgver) == 0 &&
           strcmp(identity->architecture, architecture) == 0;
}

int apk_validate_identity(const char *path, const Toolchain *tc,
                          const char *pkgname, const char *pkgver,
                          const char *architecture, int readonly) {
    char private_dir[128];
    int artifact_fd = -1;
    int result;
    struct stat source;
    struct stat current;
    ApkIdentity identity;
    memset(&identity, 0, sizeof(identity));
    if (path == 0 || pkgname == 0 || pkgver == 0 || architecture == 0 ||
        !valid_tools(tc)) return 1;
    if (readonly) {
        artifact_fd = open(path, O_RDONLY);
        if (artifact_fd < 0) return 1;
        result = validate_artifact(artifact_fd, tc, 0, &identity);
        close(artifact_fd);
    } else {
        if (make_private_dir(private_dir, sizeof(private_dir), "identity") != 0)
            return 1;
        if (make_immutable_copy(path, private_dir, &artifact_fd, &source) != 0) {
            remove_private_dir(private_dir); return 1;
        }
        result = validate_artifact(artifact_fd, tc, 0, &identity);
        if (result == 0 &&
            (lstat(path, &current) != 0 || !S_ISREG(current.st_mode) ||
             !same_artifact(&source, &current)))
            result = 1;
        close(artifact_fd);
        if (remove_private_dir(private_dir) != 0) result = 1;
    }
    if (result == 0 && !identity_matches(&identity, pkgname, pkgver,
                                         architecture)) result = 1;
    identity_free(&identity);
    return result;
}

static int use_artifact(const char *path, const char *root,
                         const Toolchain *tc, const char *pkgname,
                         const char *pkgver, const char *architecture,
                         unsigned required, int objects, int superset) {
    char private_dir[128];
    char stage[160];
    int artifact_fd = -1;
    int result;
    struct stat source;
    struct stat current;
    strlist explicit_dirs;
    ApkIdentity identity;
    unsigned declared = 0;

    strlist_init(&explicit_dirs);
    memset(&identity, 0, sizeof(identity));
    if (path == 0 || path[0] == '\0' || (!required && !root) || (root && !root[0]) ||
        !valid_tools(tc)) {
        strlist_free(&explicit_dirs);
        return 1;
    }
    if (make_private_dir(private_dir, sizeof(private_dir), "extract") != 0) {
        strlist_free(&explicit_dirs);
        return 1;
    }
    sprintf(stage, "%s/root", private_dir);
    if (make_immutable_copy(path, private_dir, &artifact_fd, &source) != 0 ||
        validate_artifact(artifact_fd, tc, &explicit_dirs,
                          (required || pkgname) ? &identity : 0) != 0 ||
        (!required && pkgname != 0 && !identity_matches(&identity, pkgname, pkgver,
                                           architecture)) ||
        mkdir(stage, 0700) != 0) {
        if (artifact_fd >= 0) close(artifact_fd);
        remove_private_dir(private_dir);
        strlist_free(&explicit_dirs);
        identity_free(&identity);
        return 1;
    }
    result = 0;
    if (required && (!identity.architecture || !identity.architecture[0] ||
        architecture_parse(identity.architecture, &declared) != 0 ||
        (pkgname && strcmp(identity.pkgname, pkgname) != 0) ||
        (pkgver && strcmp(identity.pkgver, pkgver) != 0) ||
        (!superset && strcmp(identity.architecture, architecture_label(required)) != 0)))
        result = 1;
    if (!result && required &&
        !architecture_path_has_token(path, declared))
        result = 1;
    if (!result) result = tar_pipeline(artifact_fd, stage, 0, tc);
    if (!result && required) {
        result = products_validate(stage, declared, objects, 0);
        if (!result && superset)
            result = products_validate(stage, required, objects, 1);
    }
    if (result == 0 &&
        (lstat(path, &current) != 0 || !S_ISREG(current.st_mode) ||
         !same_artifact(&source, &current)))
        result = 1;
    if (result == 0 && root && merge_stage(stage, root, &explicit_dirs) != 0) {
        fprintf(stderr,
                "rbuild: APK merge failed; earlier destination entries may "
                "have been overwritten or deleted\n");
        result = 1;
    }
    close(artifact_fd);
    if (remove_private_dir(private_dir) != 0) result = 1;
    strlist_free(&explicit_dirs);
    identity_free(&identity);
    return result;
}

int apk_extract_identity(const char *path, const char *root,
                         const Toolchain *tc, const char *pkgname,
                         const char *pkgver, const char *architecture) {
    return use_artifact(path, root, tc, pkgname, pkgver, architecture, 0, 0, 0);
}

int apk_use_arch(const char *path, const char *root, const Toolchain *tc,
                  const char *pkgname, const char *pkgver, unsigned required,
                  int object_collection, int allow_superset) {
    Toolchain fallback;
    if (!architecture_label(required)) return 1;
    if (exec_dry_run) {
        printf("validate APK %s for %s%s\n", path,
               architecture_label(required), root ? " and install" : "");
        return 0;
    }
    if (!tc) {
        toolchain_init(&fallback);
        fallback.tar = FALLBACK_TAR; fallback.gzip = "gzip";
        tc = &fallback;
    }
    return use_artifact(path, root, tc, pkgname, pkgver, 0, required,
                        object_collection, allow_superset);
}

int apk_extract(const char *path, const char *root, const Toolchain *tc) {
    return apk_extract_identity(path, root, tc, 0, 0, 0);
}

int apk_untar(const char *path, const char *root, const Toolchain *tc) {
    Toolchain fallback;
    int fd;
    int rc;

    if (exec_dry_run) {
        printf("extract %s into %s\n", path, root);
        fflush(stdout);
        return 0;
    }
    if (!tc) {
        toolchain_init(&fallback);
        fallback.tar = FALLBACK_TAR; fallback.gzip = "gzip";
        tc = &fallback;
    }
    if (!valid_tools(tc)) {
        fprintf(stderr, "rbuild: missing configured tar/gzip\n");
        return 1;
    }
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    rc = tar_pipeline(fd, root, 0, tc);
    close(fd);
    if (rc) fprintf(stderr, "rbuild: unable to extract %s\n", path);
    return rc;
}

/* apk_untar_check models the extractor rbuild runs, Rhapsody /bin/pax -r
   (src/Commands/file_cmds/pax, tar.c tar_id/tar_rd/ustar_id/ustar_rd). The
   longest member name it handles is a ustar prefix/name: 154 + 1 + 99. */
#define TAR_CHECK_NAME_MAX 256

/* The checker compares symlink names with ASCII case folded, so it stays
   sound on a case-folding build filesystem such as HFS+. It refuses non-ASCII
   names, whose Unicode folding ASCII folding cannot match. */
static int has_non_ascii(const char *s) {
    for (; *s != '\0'; s++)
        if ((unsigned char)*s >= 0x80) return 1;
    return 0;
}

static int fold_char(int c) {
    return c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c;
}

/* strncmp with ASCII case folded; LENGTH bounds both strings. */
static int fold_ncmp(const char *a, const char *b, size_t length) {
    for (; length > 0; length--, a++, b++) {
        int diff = fold_char((unsigned char)*a) - fold_char((unsigned char)*b);
        if (diff != 0 || *a == '\0') return diff;
    }
    return 0;
}

static int fold_list_contains(const strlist *list, const char *value) {
    size_t i;
    for (i = 0; i < list->count; i++)
        if (fold_ncmp(list->items[i], value, strlen(value) + 1) == 0) return 1;
    return 0;
}

static int fold_descends_through_symlink(const char *name,
                                         const strlist *symlinks) {
    size_t i;
    for (i = 0; i < symlinks->count; i++) {
        size_t length = strlen(symlinks->items[i]);
        if (fold_ncmp(name, symlinks->items[i], length) == 0 &&
            name[length] == '/') return 1;
    }
    return 0;
}

/* Resolves link TARGET lexically from the directory of MEMBER (a symlink) or
   from the archive root (a hard link): "." stays, ".." pops, anything else
   pushes. Returns 0 when the target stays inside the root and does not pass
   through a symlink member before its final component; otherwise a reason,
   which may be formatted into BUF. */
static const char *link_target_reason(const char *member, const char *target,
                                      int hardlink, const strlist *symlinks,
                                      char *buf) {
    char path[2 * TAR_CHECK_NAME_MAX + 2];
    const char *slash = strrchr(member, '/');
    const char *p = target;
    size_t used = 0;

    if (!hardlink && slash != 0) {
        used = (size_t)(slash - member);
        memcpy(path, member, used);
    }
    while (*p != '\0') {
        const char *start;
        size_t length;
        while (*p == '/') p++;
        if (*p == '\0') break;
        start = p;
        while (*p != '\0' && *p != '/') p++;
        length = (size_t)(p - start);
        if (length == 1 && start[0] == '.') continue;
        if (length == 2 && start[0] == '.' && start[1] == '.') {
            if (used == 0) return "symlink target escapes the archive root";
            while (used > 0 && path[used - 1] != '/') used--;
            if (used > 0) used--;
            continue;
        }
        if (used != 0) path[used++] = '/';
        memcpy(path + used, start, length);
        used += length;
        path[used] = '\0';
        while (*p == '/') p++;
        /* case folded, in case the build filesystem folds case */
        if (*p != '\0' && fold_list_contains(symlinks, path)) {
            sprintf(buf, "link target passes through symlink '%s'", path);
            return buf;
        }
    }
    return 0;
}

/* pax's asc_ul skips leading spaces and '0's and stops at any other
   non-digit, so a NUL there reads as 0 where parse_octal would skip it. */
static int nul_led_field(const char *field, size_t width) {
    size_t i = 0;
    while (i < width && field[i] == ' ') i++;
    return i < width && field[i] == '\0';
}

/* Whether pax skips member data after the header: ustar_rd gives links,
   directories, devices and FIFOs none, and tar_rd gives links, directories
   and names ending in '/' none, whatever the size field says. */
static int pax_has_data(char type, int ustar, const char *name_field) {
    if (type == '1' || type == '2' || type == '5') return 0;
    if (ustar) return type != '3' && type != '4' && type != '6';
    return name_field[strlen(name_field) - 1] != '/';
}

static int check_tar_stream(int fd, const char *path) {
    char header[TAR_BLOCK_SIZE];
    char raw_name[TAR_CHECK_NAME_MAX + 1];
    char name[TAR_CHECK_NAME_MAX + 1];
    char linkname[101];
    char target[101];
    char link_entry[102];
    char reason_buf[TAR_CHECK_NAME_MAX + 64];
    strlist symlinks;
    strlist raw_names;  /* every member, as in its header */
    strlist names;      /* every member, normalized */
    strlist links;      /* per member: "" or its link type, then target */
    int zero_blocks = 0;
    int first_ustar = -1;
    int result = 1;
    size_t i;

    strlist_init(&symlinks);
    strlist_init(&raw_names);
    strlist_init(&names);
    strlist_init(&links);
    for (;;) {
        int got = read_exact(fd, header, sizeof(header));
        unsigned long size;
        unsigned long padding;
        const char *bad = 0;
        const char *reason = 0;
        char type;
        int ustar;

        if (got == 0 && zero_blocks == 1) {
            result = 0;
            break;
        }
        if (got != 1) {
            fprintf(stderr, "rbuild: %s: truncated tar archive\n", path);
            break;
        }
        if (block_is_zero(header)) {
            if (first_ustar < 0) {
                /* pax's get_arc would search past it byte by byte */
                fprintf(stderr, "rbuild: %s: bad tar header (archive starts "
                        "with a zero block)\n", path);
                break;
            }
            if (++zero_blocks == 2) {
                /* Drain what follows the end marker so gzip exits cleanly. */
                char trailing[TAR_BLOCK_SIZE];
                ssize_t n;
                while ((n = read(fd, trailing, sizeof(trailing))) != 0) {
                    if (n < 0 && errno != EINTR) break;
                }
                if (n == 0) result = 0;
                else fprintf(stderr, "rbuild: %s: read error\n", path);
                break;
            }
            continue;
        }
        zero_blocks = 0;
        type = header[156];
        ustar = memcmp(header + 257, "ustar", 5) == 0;

        /* Accept only headers pax identifies and reads the same way, so it
           never resyncs into member data. pax copies a name up to 3072
           bytes, not the field width, so an unterminated field runs on. */
        if (memchr(header, '\0', 100) == 0 ||
            (ustar && memchr(header + 345, '\0', 155) == 0) ||
            ((type == '1' || type == '2') &&
             memchr(header + 157, '\0', 100) == 0))
            bad = "name field not NUL-terminated";
        else if (header[0] == '\0')
            bad = "empty name field";
        else if (nul_led_field(header + 124, 12) ||
                 nul_led_field(header + 148, 8))
            bad = "NUL before the size or checksum digits";
        else if (!valid_checksum(header))
            bad = "checksum mismatch";
        else if (parse_octal(header + 124, 12, &size) != 0)
            bad = "bad size field";
        else if (first_ustar >= 0 && ustar != first_ustar)
            bad = "format differs from the first header";
        else if (ustar && memcmp(header + 257, "ustar\0", 6) != 0 &&
                 header[345] != '\0')
            /* pax joins the prefix; GNU tar ignores it without POSIX magic */
            bad = "prefix field without POSIX ustar magic";
        if (bad != 0) {
            fprintf(stderr, "rbuild: %s: bad tar header (%s)\n", path, bad);
            break;
        }
        first_ustar = ustar;
        padding = (TAR_BLOCK_SIZE - (size % TAR_BLOCK_SIZE)) % TAR_BLOCK_SIZE;
        field_string(header, 100, raw_name);
        field_string(header + 157, 100, linkname);
        if (ustar && header[345] != '\0') {
            /* joined as pax's ustar_rd and modern GNU tar do; Rhapsody's
               gnutar 1.12 ignores the prefix, one reason the guarantee is
               scoped to pax */
            char prefix[156];
            char base[101];
            field_string(header + 345, 155, prefix);
            field_string(header, 100, base);
            sprintf(raw_name, "%s/%s", prefix, base);
        }

        /* normalize_name drops "./", "." and empty components and a trailing
           '/', and fails on an absolute name or a ".." component. */
        if (type == 'x' || type == 'g') {
            reason = "pax extended header unsupported";
        } else if (type == 'L' || type == 'K') {
            reason = "GNU long name unsupported";
        } else if (type != '\0' && (type < '0' || type > '7')) {
            reason = "member type unsupported";
        } else if (!pax_has_data(type, ustar, raw_name) && size != 0) {
            /* GNU tar would skip SIZE bytes that pax reads as headers */
            reason = "size set on a member without data";
        } else if ((type == '0' || type == '\0') && size != 0 &&
                   raw_name[strlen(raw_name) - 1] == '/') {
            /* pax reads data here; GNU tar makes a directory */
            reason = "regular member named like a directory has data";
        } else if (has_non_ascii(raw_name) ||
                   ((type == '1' || type == '2') && has_non_ascii(linkname))) {
            reason = "non-ASCII name unsupported";
        } else if (raw_name[0] == '/') {
            reason = "absolute path";
        } else if (normalize_name(raw_name, name, sizeof(name)) != 0) {
            reason = "contains a '..' component";
        } else if (fold_descends_through_symlink(name, &symlinks)) {
            reason = "path through a symlink";
        } else if (type == '2' && linkname[0] == '/') {
            reason = "absolute symlink target";
        } else if (type == '1' && linkname[0] == '/') {
            reason = "absolute hard link target";
        } else if (type == '1' &&
                   normalize_name(linkname, target, sizeof(target)) != 0) {
            reason = "hard link target contains a '..' component";
        }
        if (reason != 0) {
            fprintf(stderr, "rbuild: %s: unsafe member '%s' (%s)\n",
                    path, raw_name, reason);
            break;
        }

        link_entry[0] = '\0';
        if (type == '1' || type == '2') {
            link_entry[0] = type;
            strcpy(link_entry + 1, linkname);
        }
        strlist_push(&raw_names, raw_name);
        strlist_push(&names, name);
        strlist_push(&links, link_entry);
        if (type == '2' && name[0] != '\0') strlist_push(&symlinks, name);

        if (pax_has_data(type, ustar, raw_name) &&
            (skip_exact(fd, size) != 0 || skip_exact(fd, padding) != 0)) {
            fprintf(stderr, "rbuild: %s: truncated tar archive\n", path);
            break;
        }
    }

    /* Names and link targets against every symlink in the archive, so
       member order does not matter. */
    for (i = 0; result == 0 && i < names.count; i++) {
        const char *link_info = links.items[i];
        const char *reason = 0;
        if (fold_descends_through_symlink(names.items[i], &symlinks))
            reason = "path through a symlink";
        else if (link_info[0] != '\0')
            reason = link_target_reason(names.items[i], link_info + 1,
                                        link_info[0] == '1', &symlinks,
                                        reason_buf);
        if (reason != 0) {
            fprintf(stderr, "rbuild: %s: unsafe member '%s' (%s)\n",
                    path, raw_names.items[i], reason);
            result = 1;
        }
    }
    strlist_free(&symlinks);
    strlist_free(&raw_names);
    strlist_free(&names);
    strlist_free(&links);
    return result;
}

int apk_untar_check(const char *path, const Toolchain *tc) {
    Toolchain fallback;
    int fd;
    int stream_fd;
    pid_t gzip_pid;
    int rc;

    if (exec_dry_run) {
        printf("check members of %s\n", path);
        fflush(stdout);
        return 0;
    }
    if (!tc) {
        toolchain_init(&fallback);
        fallback.tar = FALLBACK_TAR; fallback.gzip = "gzip";
        tc = &fallback;
    }
    if (!valid_tools(tc)) {
        fprintf(stderr, "rbuild: missing configured tar/gzip\n");
        return 1;
    }
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    if (start_gzip(fd, tc, &stream_fd, &gzip_pid) != 0) {
        close(fd);
        fprintf(stderr, "rbuild: unable to decompress %s\n", path);
        return 1;
    }
    close(fd);
    rc = check_tar_stream(stream_fd, path);
    close(stream_fd);
    /* After a rejection gzip may die of SIGPIPE; only its status on a
       fully read stream matters. */
    if (wait_child(gzip_pid) != 0 && rc == 0) {
        fprintf(stderr, "rbuild: unable to decompress %s\n", path);
        rc = 1;
    }
    return rc;
}

static void remove_own_link(const char *path, const struct stat *source) {
    struct stat current;
    if (lstat(path, &current) == 0 && current.st_dev == source->st_dev &&
        current.st_ino == source->st_ino)
        unlink(path);
}

static int pin_quarantine_source(const char *path, char *temporary,
                                 size_t capacity) {
    const char *slash = strrchr(path, '/');
    size_t prefix_length = slash == 0 ? 0 : (size_t)(slash - path + 1);
    int attempt;

    for (attempt = 0; attempt < 100; attempt++) {
        if (prefix_length + 80 > capacity) return 1;
        if (prefix_length != 0)
            memcpy(temporary, path, prefix_length);
        sprintf(temporary + prefix_length,
                ".rbuild-quarantine-%ld-%ld-%d",
                (long)getpid(), (long)time(0), attempt);
        if (link(path, temporary) == 0) return 0;
        if (errno != EEXIST) return 1;
    }
    errno = EEXIST;
    return 1;
}

static int write_bytes(int fd, const char *data, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = write(fd, data + offset, length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return 1;
        offset += (size_t)written;
    }
    return 0;
}

static int quarantine_symlink(const char *path, const char *destination,
                              const struct stat *source) {
    char target[4097];
    char *record_text;
    ssize_t target_length;
    int fd = -1;
    int made_record = 0;
    int record_valid = 0;
    int write_failed = 0;
    int result = 1;
    struct stat record;
    struct stat current;

    target_length = readlink(path, target, sizeof(target) - 1);
    if (target_length < 0 || target_length >= (ssize_t)(sizeof(target) - 1)) {
        fprintf(stderr, "rbuild: cannot read APK symlink %s\n", path);
        return 1;
    }
    target[target_length] = '\0';
    record_text = str_cats("symlink -> ", target, "\n", (char *)0);
    fd = open(destination, O_WRONLY | O_CREAT | O_EXCL, 0666);
    if (fd >= 0) {
        if (fstat(fd, &record) != 0) write_failed = 1;
        else record_valid = 1;
        if (write_bytes(fd, record_text, strlen(record_text)) != 0 ||
            fsync(fd) != 0) write_failed = 1;
        if (close(fd) != 0) write_failed = 1;
        fd = -1;
        if (write_failed) {
            if (record_valid) remove_own_link(destination, &record);
            free(record_text);
            return 1;
        }
        made_record = 1;
    } else if (errno != EEXIST) {
        fprintf(stderr, "rbuild: cannot reserve quarantine file %s: %s\n",
                destination, strerror(errno));
        free(record_text);
        return 1;
    } else {
        fprintf(stderr, "rbuild: preserving existing quarantine file %s\n",
                destination);
    }
    if (lstat(path, &current) != 0 || !S_ISLNK(current.st_mode) ||
        current.st_dev != source->st_dev || current.st_ino != source->st_ino) {
        fprintf(stderr, "rbuild: quarantine source changed %s\n", path);
        if (made_record) remove_own_link(destination, &record);
        goto done;
    }
    if (unlink(path) != 0) {
        fprintf(stderr, "rbuild: cannot remove quarantined APK symlink %s: %s\n",
                path, strerror(errno));
        if (made_record) remove_own_link(destination, &record);
        goto done;
    }
    result = 0;
done:
    free(record_text);
    return result;
}

int apk_quarantine(const char *path) {
    static const char suffix[] = ".invalid";
    char *destination;
    char *temporary;
    size_t length;
    struct stat source;
    struct stat linked;
    struct stat pinned;

    if (path == 0 || path[0] == '\0') {
        fprintf(stderr, "rbuild: invalid APK path for quarantine\n");
        return 1;
    }
    length = strlen(path) + sizeof(suffix);
    destination = (char *)malloc(length);
    temporary = (char *)malloc(strlen(path) + 128);
    if (destination == 0 || temporary == 0) {
        fprintf(stderr, "rbuild: cannot allocate APK quarantine path\n");
        free(temporary);
        free(destination);
        return 1;
    }
    strcpy(destination, path);
    strcat(destination, suffix);

    if (lstat(path, &source) != 0) {
        fprintf(stderr, "rbuild: cannot inspect APK %s: %s\n",
                path, strerror(errno));
        free(temporary);
        free(destination);
        return 1;
    }
    if (S_ISLNK(source.st_mode)) {
        int result = quarantine_symlink(path, destination, &source);
        free(temporary);
        free(destination);
        return result;
    }
    if (!S_ISREG(source.st_mode)) {
        fprintf(stderr, "rbuild: cannot quarantine non-regular APK %s\n",
                path);
        free(temporary);
        free(destination);
        return 1;
    }
    run_quarantine_pre_link_test_hook();
    if (pin_quarantine_source(path, temporary, strlen(path) + 128) != 0) {
        fprintf(stderr, "rbuild: cannot pin quarantine source %s: %s\n",
                path, strerror(errno));
        free(temporary);
        free(destination);
        return 1;
    }
    if (lstat(temporary, &pinned) != 0) {
        unlink(temporary);
        free(temporary);
        free(destination);
        return 1;
    }
    if (pinned.st_dev != source.st_dev || pinned.st_ino != source.st_ino) {
        fprintf(stderr, "rbuild: quarantine source changed %s\n", path);
        unlink(temporary);
        free(temporary);
        free(destination);
        return 1;
    }
    if (link(temporary, destination) != 0) {
        if (errno == EEXIST)
            fprintf(stderr,
                    "rbuild: refusing to overwrite quarantine file %s\n",
                    destination);
        else
            fprintf(stderr, "rbuild: cannot reserve quarantine file %s: %s\n",
                    destination, strerror(errno));
        unlink(temporary);
        free(temporary);
        free(destination);
        return 1;
    }
    if (unlink(temporary) != 0) {
        remove_own_link(destination, &pinned);
        unlink(temporary);
        free(temporary);
        free(destination);
        return 1;
    }
    run_quarantine_after_publish_test_hook();
    run_quarantine_test_hook();
    if (lstat(path, &linked) != 0 ||
        linked.st_dev != source.st_dev || linked.st_ino != source.st_ino) {
        fprintf(stderr, "rbuild: quarantine source changed %s\n", path);
        remove_own_link(destination, &pinned);
        free(temporary);
        free(destination);
        return 1;
    }
    if (lstat(destination, &linked) != 0 ||
        linked.st_dev != pinned.st_dev ||
        linked.st_ino != pinned.st_ino) {
        fprintf(stderr, "rbuild: quarantine destination changed %s\n",
                destination);
        free(temporary);
        free(destination);
        return 1;
    }
    if (unlink(path) != 0) {
        int saved_errno = errno;
        fprintf(stderr, "rbuild: cannot remove quarantined APK %s: %s\n",
                path, strerror(saved_errno));
        remove_own_link(destination, &pinned);
        free(temporary);
        free(destination);
        return 1;
    }
    free(temporary);
    free(destination);
    return 0;
}
