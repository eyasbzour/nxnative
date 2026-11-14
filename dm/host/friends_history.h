// Local friends-service registration keys. The player's firmware supplies the signing keys;
// without that keyring, keys of this device's own sign (DM_ROOT/friends-history/device.keyring,
// random once), which other hosts take and a console would not. No key material is compiled in.
#pragma once
#include <stdbool.h>
#include <stdint.h>

enum { DM_FRIENDS_HISTORY_KEY_SIZE = 64, DM_FRIENDS_HISTORY_KEYRING_SIZE = 256 };
enum { DM_FRIENDS_HISTORY_OK = 0, DM_FRIENDS_HISTORY_FAIL = 0x2a2,
       DM_FRIENDS_HISTORY_INVALID_UID = 0x479 };
// Optional embedding provider, registered before guest startup. It must copy
// eight consecutive 32-byte keys and must not call guest code. NULL restores the
// default reader: DM_SYSTEM_DATA_DIR/010000000000000e/files/play-history.keyring, else the device's
// own keys when that file does not exist (a present but unusable one fails).
typedef bool (*dm_friends_history_key_provider)(uint8_t keyring[8][32]);
void dm_friends_history_set_key_provider(dm_friends_history_key_provider provider);
// uid points to 16 bytes. The HLE wrapper also checks that this local user exists.
// input_flag is the SDK's opaque boolean, preserved as flag & 1. This host's user
// has no linked Nintendo NSA ID: that field and its presence flag remain zero.
// UUIDv4 is persisted atomically under DM_ROOT/friends-history (or the working
// directory on iOS), before success. Failure clears a non-NULL 64-byte output.
uint32_t dm_friends_history_key(void *out, const void *uid, unsigned input_flag);

#ifdef DM_FRIENDS_HISTORY_TEST
typedef void (*dm_friends_history_random_provider)(void *out, unsigned size);
void dm_friends_history_set_random_provider(dm_friends_history_random_provider provider);
#endif
