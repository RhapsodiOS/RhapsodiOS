BUILD := BUILD

# GNU make predefines CC=cc (origin "default"); this host has no cc.  An
# explicit CC=... on the command line or in the environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif

TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -D_CRT_SECURE_NO_WARNINGS -I..

test: $(BUILD)/match_test
	$(BUILD)/match_test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/match_test: match_test.c ../match.c ../match.h | $(BUILD)
	$(CC) $(TEST_CFLAGS) -o $@ match_test.c ../match.c

clean:
	rm -rf $(BUILD)

.PHONY: test clean
