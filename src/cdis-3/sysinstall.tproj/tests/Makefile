BUILD := BUILD

# GNU make predefines CC=cc (origin "default"); this host has no cc.  An
# explicit CC=... on the command line or in the environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif

TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -I..

test: test-layout

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/layout_test: layout_test.c ../layout.c ../layout.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ layout_test.c ../layout.c

test-layout: $(BUILD)/layout_test
	$(BUILD)/layout_test

clean:
	rm -rf $(BUILD)

.PHONY: test test-layout clean
