BUILD := BUILD

# GNU make predefines CC=cc (origin "default"); this host has no cc.  An
# explicit CC=... on the command line or in the environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif

TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -D_CRT_SECURE_NO_WARNINGS -I..

test: test-layout test-sets test-config

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

clean:
	rm -rf $(BUILD)

.PHONY: test test-layout test-sets test-config clean
