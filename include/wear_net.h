#ifndef WEAR_NET_H
#define WEAR_NET_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define WEAR_NET_API __declspec(dllimport)
#else
#define WEAR_NET_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define WEAR_NET_ABI_VERSION 1u

enum wear_net_status {
  WEAR_NET_OK = 0,
  WEAR_NET_NO_EVENT = 1,
  WEAR_NET_INVALID_ARGUMENT = -1,
  WEAR_NET_NOT_FOUND = -2,
  WEAR_NET_BUFFER_TOO_SMALL = -3,
  WEAR_NET_INTERNAL = -4,
};

enum wear_net_event_kind {
  WEAR_NET_EVENT_PACKET = 1,
  WEAR_NET_EVENT_STATE = 2,
  WEAR_NET_EVENT_STATISTICS = 3,
  WEAR_NET_EVENT_WARNING = 4,
};

typedef void (*wear_net_wake_callback)(uint64_t handle);

/* Pass NULL only for hosts that provide their own event delivery mechanism. */

typedef struct wear_net_config {
  uint32_t abi_version;
  uint16_t mtu;
  uint16_t reserved;
  uint32_t ingress_capacity;
  uint32_t stack_capacity;
  uint32_t outbound_capacity;
  uint32_t meter_window_ms;
  uint32_t statistics_interval_ms;
  const char *capture_path;
} wear_net_config;

typedef struct wear_net_snapshot {
  uint32_t abi_version;
  uint8_t active;
  uint8_t reserved[3];
  uint32_t active_sessions;
  uint64_t bytes_from_device;
  uint64_t bytes_to_device;
  uint64_t dropped_packets;
} wear_net_snapshot;

WEAR_NET_API uint32_t wear_net_abi_version(void);
WEAR_NET_API int32_t wear_net_open(const wear_net_config *config,
                                       wear_net_wake_callback callback,
                                       uint64_t *out_handle);
WEAR_NET_API int32_t wear_net_push(uint64_t handle, const uint8_t *data,
                                       size_t length);
WEAR_NET_API int32_t wear_net_event_peek(uint64_t handle,
                                             uint32_t *out_kind,
                                             size_t *out_length);
WEAR_NET_API int32_t wear_net_event_read(uint64_t handle, uint8_t *buffer,
                                             size_t capacity,
                                             uint32_t *out_kind,
                                             size_t *out_length);
WEAR_NET_API int32_t
wear_net_get_snapshot(uint64_t handle, wear_net_snapshot *out_snapshot);
WEAR_NET_API int32_t wear_net_close(uint64_t handle);
WEAR_NET_API const char *wear_net_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
