#include "LuxelWebMCodecShims.h"

#include <opus/opus.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vpx/vp8cx.h>
#include <vpx/vpx_encoder.h>
#include <vpx/vpx_image.h>

struct LuxelVPXEncoder {
    vpx_codec_ctx_t codec;
    int width;
    int height;
    int frame_rate;
};

struct LuxelOpusEncoder {
    OpusEncoder *encoder;
    int channel_count;
};

static void luxel_set_error(char *error_message, size_t error_message_size, const char *format, ...) {
    if (error_message == NULL || error_message_size == 0) {
        return;
    }

    va_list args;
    va_start(args, format);
    vsnprintf(error_message, error_message_size, format, args);
    va_end(args);
    error_message[error_message_size - 1] = '\0';
}

static int luxel_append_packet(
    LuxelCodecPacketList *list,
    const uint8_t *data,
    size_t size,
    int64_t presentation_time_units,
    uint32_t duration_units,
    int is_key_frame
) {
    LuxelCodecPacket *packets = realloc(list->packets, (list->count + 1) * sizeof(LuxelCodecPacket));
    if (packets == NULL) {
        return -1;
    }

    list->packets = packets;
    LuxelCodecPacket *packet = &list->packets[list->count];
    packet->data = malloc(size);
    if (packet->data == NULL) {
        return -1;
    }

    memcpy(packet->data, data, size);
    packet->size = size;
    packet->presentation_time_units = presentation_time_units;
    packet->duration_units = duration_units;
    packet->is_key_frame = is_key_frame;
    list->count += 1;
    return 0;
}

static int luxel_collect_vpx_packets(
    LuxelVPXEncoder *encoder,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
) {
    vpx_codec_iter_t iterator = NULL;
    const vpx_codec_cx_pkt_t *packet = NULL;

    while ((packet = vpx_codec_get_cx_data(&encoder->codec, &iterator)) != NULL) {
        if (packet->kind != VPX_CODEC_CX_FRAME_PKT) {
            continue;
        }

        const uint8_t *data = (const uint8_t *)packet->data.frame.buf;
        const size_t size = (size_t)packet->data.frame.sz;
        if (size == 0) {
            continue;
        }

        if (luxel_append_packet(
                packets,
                data,
                size,
                (int64_t)packet->data.frame.pts,
                (uint32_t)packet->data.frame.duration,
                (packet->data.frame.flags & VPX_FRAME_IS_KEY) != 0
            ) != 0) {
            luxel_set_error(error_message, error_message_size, "Could not allocate VP9 packet output.");
            return -1;
        }
    }

    return 0;
}

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
) {
    if (encoder == NULL || width <= 0 || height <= 0 || frame_rate <= 0) {
        luxel_set_error(error_message, error_message_size, "Invalid VP9 encoder configuration.");
        return -1;
    }

    vpx_codec_enc_cfg_t configuration;
    vpx_codec_err_t result = vpx_codec_enc_config_default(vpx_codec_vp9_cx(), &configuration, 0);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not create default VP9 configuration: %s.", vpx_codec_err_to_string(result));
        return -1;
    }

    configuration.g_w = (unsigned int)width;
    configuration.g_h = (unsigned int)height;
    configuration.g_timebase.num = 1;
    configuration.g_timebase.den = frame_rate;
    configuration.g_threads = thread_count;
    configuration.g_lag_in_frames = 0;
    configuration.g_error_resilient = 0;
    configuration.kf_mode = VPX_KF_AUTO;
    configuration.kf_max_dist = keyframe_interval;
    configuration.rc_end_usage = VPX_CQ;
    configuration.rc_target_bitrate = (unsigned int)((width * height * frame_rate) / 14000);
    if (configuration.rc_target_bitrate < 128) {
        configuration.rc_target_bitrate = 128;
    }

    LuxelVPXEncoder *created_encoder = calloc(1, sizeof(LuxelVPXEncoder));
    if (created_encoder == NULL) {
        luxel_set_error(error_message, error_message_size, "Could not allocate VP9 encoder.");
        return -1;
    }

    result = vpx_codec_enc_init(&created_encoder->codec, vpx_codec_vp9_cx(), &configuration, 0);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not initialize VP9 encoder: %s.", vpx_codec_err_to_string(result));
        free(created_encoder);
        return -1;
    }

    result = vpx_codec_control(&created_encoder->codec, VP8E_SET_CPUUSED, cpu_used);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not set VP9 cpu-used: %s.", vpx_codec_err_to_string(result));
        LuxelVPXEncoderDestroy(created_encoder);
        return -1;
    }

    result = vpx_codec_control(&created_encoder->codec, VP8E_SET_CQ_LEVEL, cq_level);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not set VP9 CQ level: %s.", vpx_codec_err_to_string(result));
        LuxelVPXEncoderDestroy(created_encoder);
        return -1;
    }

    result = vpx_codec_control(&created_encoder->codec, VP9E_SET_ROW_MT, row_multithreading);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not enable VP9 row multithreading: %s.", vpx_codec_err_to_string(result));
        LuxelVPXEncoderDestroy(created_encoder);
        return -1;
    }

    int tile_columns = 0;
    while (tile_columns < 6
           && (256 << (tile_columns + 1)) <= width
           && (1u << (tile_columns + 1)) <= thread_count) {
        tile_columns += 1;
    }
    result = vpx_codec_control(&created_encoder->codec, VP9E_SET_TILE_COLUMNS, tile_columns);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not set VP9 tile columns: %s.", vpx_codec_err_to_string(result));
        LuxelVPXEncoderDestroy(created_encoder);
        return -1;
    }

    result = vpx_codec_control(&created_encoder->codec, VP9E_SET_FRAME_PARALLEL_DECODING, 1);
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not enable VP9 frame-parallel decoding: %s.", vpx_codec_err_to_string(result));
        LuxelVPXEncoderDestroy(created_encoder);
        return -1;
    }

    created_encoder->width = width;
    created_encoder->height = height;
    created_encoder->frame_rate = frame_rate;
    *encoder = created_encoder;
    return 0;
}

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
) {
    if (encoder == NULL || packets == NULL || y_plane == NULL || u_plane == NULL || v_plane == NULL) {
        luxel_set_error(error_message, error_message_size, "Invalid VP9 frame input.");
        return -1;
    }

    const size_t expected_y_size = (size_t)encoder->width * (size_t)encoder->height;
    const size_t expected_chroma_size = expected_y_size / 4;
    if (y_plane_size != expected_y_size || u_plane_size != expected_chroma_size || v_plane_size != expected_chroma_size) {
        luxel_set_error(error_message, error_message_size, "Invalid VP9 I420 plane sizes.");
        return -1;
    }

    vpx_image_t image;
    if (vpx_img_wrap(&image, VPX_IMG_FMT_I420, (unsigned int)encoder->width, (unsigned int)encoder->height, 1, (unsigned char *)y_plane) == NULL) {
        luxel_set_error(error_message, error_message_size, "Could not wrap VP9 input image.");
        return -1;
    }

    image.planes[VPX_PLANE_Y] = (unsigned char *)y_plane;
    image.stride[VPX_PLANE_Y] = encoder->width;
    image.planes[VPX_PLANE_U] = (unsigned char *)u_plane;
    image.stride[VPX_PLANE_U] = encoder->width / 2;
    image.planes[VPX_PLANE_V] = (unsigned char *)v_plane;
    image.stride[VPX_PLANE_V] = encoder->width / 2;

    vpx_codec_err_t result = vpx_codec_encode(
        &encoder->codec,
        &image,
        (vpx_codec_pts_t)presentation_time_units,
        (unsigned long)duration_units,
        0,
        VPX_DL_GOOD_QUALITY
    );

    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not encode VP9 frame: %s.", vpx_codec_error(&encoder->codec));
        return -1;
    }

    return luxel_collect_vpx_packets(encoder, packets, error_message, error_message_size);
}

int LuxelVPXEncoderFinish(
    LuxelVPXEncoder *encoder,
    int64_t presentation_time_units,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
) {
    if (encoder == NULL || packets == NULL) {
        luxel_set_error(error_message, error_message_size, "Invalid VP9 encoder finish call.");
        return -1;
    }

    vpx_codec_err_t result = vpx_codec_encode(
        &encoder->codec,
        NULL,
        (vpx_codec_pts_t)presentation_time_units,
        1,
        0,
        VPX_DL_GOOD_QUALITY
    );
    if (result != VPX_CODEC_OK) {
        luxel_set_error(error_message, error_message_size, "Could not finish VP9 encoder: %s.", vpx_codec_error(&encoder->codec));
        return -1;
    }

    return luxel_collect_vpx_packets(encoder, packets, error_message, error_message_size);
}

void LuxelVPXEncoderDestroy(LuxelVPXEncoder *encoder) {
    if (encoder == NULL) {
        return;
    }

    vpx_codec_destroy(&encoder->codec);
    free(encoder);
}

int LuxelOpusEncoderCreate(
    int sample_rate,
    int channel_count,
    int bitrate,
    LuxelOpusEncoder **encoder,
    char *error_message,
    size_t error_message_size
) {
    if (encoder == NULL || sample_rate <= 0 || channel_count <= 0 || bitrate <= 0) {
        luxel_set_error(error_message, error_message_size, "Invalid Opus encoder configuration.");
        return -1;
    }

    int opus_error = OPUS_OK;
    OpusEncoder *opus_encoder = opus_encoder_create(sample_rate, channel_count, OPUS_APPLICATION_AUDIO, &opus_error);
    if (opus_error != OPUS_OK || opus_encoder == NULL) {
        luxel_set_error(error_message, error_message_size, "Could not create Opus encoder: %s.", opus_strerror(opus_error));
        return -1;
    }

    opus_error = opus_encoder_ctl(opus_encoder, OPUS_SET_BITRATE(bitrate));
    if (opus_error != OPUS_OK) {
        luxel_set_error(error_message, error_message_size, "Could not set Opus bitrate: %s.", opus_strerror(opus_error));
        opus_encoder_destroy(opus_encoder);
        return -1;
    }

    opus_error = opus_encoder_ctl(opus_encoder, OPUS_SET_VBR(1));
    if (opus_error != OPUS_OK) {
        luxel_set_error(error_message, error_message_size, "Could not enable Opus VBR: %s.", opus_strerror(opus_error));
        opus_encoder_destroy(opus_encoder);
        return -1;
    }

    LuxelOpusEncoder *created_encoder = calloc(1, sizeof(LuxelOpusEncoder));
    if (created_encoder == NULL) {
        luxel_set_error(error_message, error_message_size, "Could not allocate Opus encoder.");
        opus_encoder_destroy(opus_encoder);
        return -1;
    }

    created_encoder->encoder = opus_encoder;
    created_encoder->channel_count = channel_count;
    *encoder = created_encoder;
    return 0;
}

int LuxelOpusEncoderEncode(
    LuxelOpusEncoder *encoder,
    const int16_t *interleaved_pcm,
    int frame_size_per_channel,
    LuxelCodecPacketList *packets,
    char *error_message,
    size_t error_message_size
) {
    if (encoder == NULL || encoder->encoder == NULL || interleaved_pcm == NULL || frame_size_per_channel <= 0 || packets == NULL) {
        luxel_set_error(error_message, error_message_size, "Invalid Opus frame input.");
        return -1;
    }

    uint8_t output[4000];
    opus_int32 byte_count = opus_encode(
        encoder->encoder,
        interleaved_pcm,
        frame_size_per_channel,
        output,
        (opus_int32)sizeof(output)
    );
    if (byte_count < 0) {
        luxel_set_error(error_message, error_message_size, "Could not encode Opus frame: %s.", opus_strerror((int)byte_count));
        return -1;
    }

    if (luxel_append_packet(packets, output, (size_t)byte_count, 0, 0, 1) != 0) {
        luxel_set_error(error_message, error_message_size, "Could not allocate Opus packet output.");
        return -1;
    }

    return 0;
}

void LuxelOpusEncoderDestroy(LuxelOpusEncoder *encoder) {
    if (encoder == NULL) {
        return;
    }

    opus_encoder_destroy(encoder->encoder);
    free(encoder);
}

void LuxelCodecPacketListDestroy(LuxelCodecPacketList *packets) {
    if (packets == NULL) {
        return;
    }

    size_t index = packets->count;
    while (index > 0) {
        index -= 1;
        free(packets->packets[index].data);
    }
    free(packets->packets);
    packets->packets = NULL;
    packets->count = 0;
}
