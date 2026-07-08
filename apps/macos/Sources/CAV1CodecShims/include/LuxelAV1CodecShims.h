#ifndef LUXEL_AV1_CODEC_SHIMS_H
#define LUXEL_AV1_CODEC_SHIMS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LuxelAV1Encoder LuxelAV1Encoder;

typedef struct {
    uint8_t *data;
    size_t size;
    int64_t presentation_time_units;
    uint32_t duration_units;
    int is_key_frame;
} LuxelAV1Packet;

typedef struct {
    LuxelAV1Packet *packets;
    size_t count;
} LuxelAV1PacketList;

int LuxelAV1EncoderCreate(
    int width,
    int height,
    int frame_rate,
    int preset,
    unsigned int qp,
    unsigned int keyframe_interval,
    unsigned int level_of_parallelism,
    LuxelAV1Encoder **encoder,
    char *error_message,
    size_t error_message_size
);

int LuxelAV1EncoderEncodeFrame(
    LuxelAV1Encoder *encoder,
    const uint8_t *y_plane,
    size_t y_plane_size,
    const uint8_t *u_plane,
    size_t u_plane_size,
    const uint8_t *v_plane,
    size_t v_plane_size,
    int64_t presentation_time_units,
    uint32_t duration_units,
    LuxelAV1PacketList *packets,
    char *error_message,
    size_t error_message_size
);

int LuxelAV1EncoderFinish(
    LuxelAV1Encoder *encoder,
    LuxelAV1PacketList *packets,
    char *error_message,
    size_t error_message_size
);

void LuxelAV1EncoderDestroy(LuxelAV1Encoder *encoder);

void LuxelAV1PacketListDestroy(LuxelAV1PacketList *packets);

#ifdef __cplusplus
}
#endif

#endif
