BUILD := BUILD

# GNU make predefines CC=cc (origin "default"); this host has no cc.  An
# explicit CC=... on the command line or in the environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif

# cmd.exe, which steps_test's popen() uses, only runs a program named .exe
ifeq ($(OS),Windows_NT)
EXE := .exe
endif

TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -D_CRT_SECURE_NO_WARNINGS -I..

test: test-layout test-sets test-config test-steps test-disks

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/layout_test: layout_test.c ../layout.c ../layout.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ layout_test.c ../layout.c

test-layout: $(BUILD)/layout_test
	$(BUILD)/layout_test

$(BUILD)/sets_test: sets_test.c ../sets.c ../sets.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ sets_test.c ../sets.c

test-sets: $(BUILD)/sets_test
	$(BUILD)/sets_test

$(BUILD)/config_test: config_test.c ../config.c ../config.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ config_test.c ../config.c

test-config: $(BUILD)/config_test
	$(BUILD)/config_test

$(BUILD)/steps_test$(EXE): steps_test.c ../steps.c ../steps.h ../layout.c ../config.c | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ steps_test.c ../steps.c ../layout.c ../config.c

test-steps: $(BUILD)/steps_test$(EXE)
	$(BUILD)/steps_test$(EXE)

$(BUILD)/disks_test: disks_test.c ../disks.c ../disks.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ disks_test.c ../disks.c

test-disks: $(BUILD)/disks_test
	$(BUILD)/disks_test

clean:
	rm -rf $(BUILD)

.PHONY: test test-layout test-sets test-config test-steps test-disks clean
