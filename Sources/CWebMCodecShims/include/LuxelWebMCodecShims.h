#ifndef LUXEL_WEBM_CODEC_SHIMS_H
#define LUXEL_WEBM_CODEC_SHIMS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LuxelVPXEncoder LuxelVPXEncoder;
typedef struct LuxelOpusEncoder LuxelOpusEncoder;

typedef struct {
    uint8_t *data;
    size_t size;
    int64_t presentation_time_units;
    uint32_t duration_units;
    int is_key_frame;
} LuxelCodecPacket;

typedef struct {
    LuxelCodecPacket *packets;
    size_t count;
} LuxelCodecPacketList;

int LuxelVPXEncoderCreate(
    int width,
    int height,
    int frame_rate,
    unsigned int cq_level,
    int cpu_used,
    unsigned int row_multithreading,
    unsigned int thread_count,
    unsigned int keyframe_interval,
    LuxelVPXEncoder **encoder,
    char *error_message,
    size_t error_message_size
);

int LuxelVPXEncoderEncodeFrame(
    LuxelVPXEncoder *encoder,
    const uint8_t *y_plane,
    size_t y_plane_size,
    const uint8_t *u_plane,
    size_t u_plane_size,
    const uint8_t *v_plane,
    size_t v_plane_size,
    int64_t presentation_time_units,
    uint32_t duration_units,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
);

int LuxelVPXEncoderFinish(
    LuxelVPXEncoder *encoder,
    int64_t presentation_time_units,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
);

void LuxelVPXEncoderDestroy(LuxelVPXEncoder *encoder);

int LuxelOpusEncoderCreate(
    int sample_rate,
    int channel_count,
    int bitrate,
    LuxelOpusEncoder **encoder,
    char *error_message,
    size_t error_message_size
);

int LuxelOpusEncoderEncode(
    LuxelOpusEncoder *encoder,
    const int16_t *interleaved_pcm,
    int frame_size_per_channel,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
);

void LuxelOpusEncoderDestroy(LuxelOpusEncoder *encoder);

void LuxelCodecPacketListDestroy(LuxelCodecPacketList *packets);

#ifdef __cplusplus
}
#endif

#endif
