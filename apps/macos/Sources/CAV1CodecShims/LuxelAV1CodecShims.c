#include "LuxelAV1CodecShims.h"

#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <svt-av1/EbSvtAv1Enc.h>

struct LuxelAV1Encoder {
    EbComponentType *component;
    int width;
    int height;
    int frame_rate;
    bool sent_eos;
    bool deinitialized;
};

static void luxel_av1_noop_log_callback(
    void *context,
    SvtAv1LogLevel level,
    const char *tag,
    const char *fmt,
    va_list args
) {
    (void)context;
    (void)level;
    (void)tag;
    (void)fmt;
    (void)args;
}

static void set_error(char *error_message, size_t error_message_size, const char *message) {
    if (!error_message || error_message_size == 0) {
        return;
    }
    snprintf(error_message, error_message_size, "%s", message);
}

static void set_error_code(char *error_message, size_t error_message_size, const char *operation, EbErrorType code) {
    if (!error_message || error_message_size == 0) {
        return;
    }
    snprintf(error_message, error_message_size, "%s failed with SVT-AV1 error 0x%08x.", operation, (unsigned int)code);
}

static bool is_key_frame(EbAv1PictureType picture_type) {
    return picture_type == EB_AV1_KEY_PICTURE || picture_type == EB_AV1_FW_KEY_PICTURE ||
           picture_type == EB_AV1_INTRA_ONLY_PICTURE;
}

static int append_packet(
    LuxelAV1Encoder *encoder,
    LuxelAV1PacketList *packets,
    const EbBufferHeaderType *output,
    char *error_message,
    size_t error_message_size
) {
    if (output->n_filled_len == 0 || output->p_buffer == NULL) {
        return 0;
    }

    LuxelAV1Packet *next_packets =
        (LuxelAV1Packet *)realloc(packets->packets, sizeof(LuxelAV1Packet) * (packets->count + 1));
    if (!next_packets) {
        set_error(error_message, error_message_size, "Could not allocate AV1 packet list.");
        return -1;
    }
    packets->packets = next_packets;

    LuxelAV1Packet *packet = &packets->packets[packets->count];
    packet->data = (uint8_t *)malloc(output->n_filled_len);
    if (!packet->data) {
        set_error(error_message, error_message_size, "Could not allocate AV1 packet data.");
        return -1;
    }

    memcpy(packet->data, output->p_buffer, output->n_filled_len);
    packet->size = output->n_filled_len;
    packet->presentation_time_units = output->pts;
    packet->duration_units = 1;
    packet->is_key_frame = is_key_frame(output->pic_type) ? 1 : 0;
    packets->count += 1;

    (void)encoder;
    return 0;
}

static int drain_packets(
    LuxelAV1Encoder *encoder,
    uint8_t pic_send_done,
    LuxelAV1PacketList *packets,
    char *error_message,
    size_t error_message_size
) {
    while (true) {
        EbBufferHeaderType *output = NULL;
        EbErrorType status = svt_av1_enc_get_packet(encoder->component, &output, pic_send_done);
        if (status == EB_NoErrorEmptyQueue) {
            return 0;
        }
        if (status != EB_ErrorNone) {
            set_error_code(error_message, error_message_size, "svt_av1_enc_get_packet", status);
            return -1;
        }
        if (!output) {
            set_error(error_message, error_message_size, "SVT-AV1 returned an empty output packet.");
            return -1;
        }

        const bool is_eos = (output->flags & EB_BUFFERFLAG_EOS) != 0;
        const bool is_alt_ref = (output->flags & EB_BUFFERFLAG_IS_ALT_REF) != 0;
        int append_status = 0;
        if (!is_eos && !is_alt_ref) {
            append_status = append_packet(encoder, packets, output, error_message, error_message_size);
        }
        svt_av1_enc_release_out_buffer(&output);

        if (append_status != 0) {
            return append_status;
        }
        if (is_eos) {
            return 0;
        }
    }
}

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
) {
    if (!encoder) {
        set_error(error_message, error_message_size, "AV1 encoder output pointer was null.");
        return -1;
    }
    *encoder = NULL;

    if (width < 64 || height < 64 || width % 2 != 0 || height % 2 != 0 || frame_rate <= 0) {
        set_error(error_message, error_message_size, "Invalid AV1 encoder dimensions or frame rate.");
        return -1;
    }
    if (preset < ENC_M0 || preset > ENC_M13 || qp < 1 || qp > 63 || keyframe_interval == 0) {
        set_error(error_message, error_message_size, "Invalid AV1 encoder quality settings.");
        return -1;
    }

    svt_av1_set_log_callback(luxel_av1_noop_log_callback, NULL);

    EbSvtAv1EncConfiguration configuration;
    EbComponentType *component = NULL;
    EbErrorType status = svt_av1_enc_init_handle(&component, &configuration);
    if (status != EB_ErrorNone || !component) {
        set_error_code(error_message, error_message_size, "svt_av1_enc_init_handle", status);
        return -1;
    }

    configuration.enc_mode = (int8_t)preset;
    configuration.pred_structure = RANDOM_ACCESS;
    configuration.intra_period_length = (int32_t)keyframe_interval - 1;
    configuration.intra_refresh_type = SVT_AV1_KF_REFRESH;
    configuration.hierarchical_levels = 2;
    configuration.source_width = (uint32_t)width;
    configuration.source_height = (uint32_t)height;
    configuration.frame_rate_numerator = (uint32_t)frame_rate;
    configuration.frame_rate_denominator = 1;
    configuration.encoder_bit_depth = 8;
    configuration.encoder_color_format = EB_YUV420;
    configuration.profile = MAIN_PROFILE;
    configuration.level = 0;
    configuration.color_primaries = EB_CICP_CP_BT_709;
    configuration.transfer_characteristics = EB_CICP_TC_BT_709;
    configuration.matrix_coefficients = EB_CICP_MC_BT_709;
    configuration.color_range = EB_CR_STUDIO_RANGE;
    configuration.rate_control_mode = SVT_AV1_RC_MODE_CQP_OR_CRF;
    configuration.qp = qp;
    configuration.extended_crf_qindex_offset = 0;
    configuration.look_ahead_distance = 0;
    configuration.aq_mode = 0;
    configuration.tune = 0;
    configuration.enable_tf = 0;
    configuration.screen_content_mode = 2;
    configuration.level_of_parallelism = level_of_parallelism > 6 ? 6 : level_of_parallelism;
    configuration.pass = 0;

    status = svt_av1_enc_set_parameter(component, &configuration);
    if (status != EB_ErrorNone) {
        set_error_code(error_message, error_message_size, "svt_av1_enc_set_parameter", status);
        svt_av1_enc_deinit_handle(component);
        return -1;
    }

    status = svt_av1_enc_init(component);
    if (status != EB_ErrorNone) {
        set_error_code(error_message, error_message_size, "svt_av1_enc_init", status);
        svt_av1_enc_deinit_handle(component);
        return -1;
    }

    LuxelAV1Encoder *created = (LuxelAV1Encoder *)calloc(1, sizeof(LuxelAV1Encoder));
    if (!created) {
        set_error(error_message, error_message_size, "Could not allocate AV1 encoder handle.");
        svt_av1_enc_deinit(component);
        svt_av1_enc_deinit_handle(component);
        return -1;
    }

    created->component = component;
    created->width = width;
    created->height = height;
    created->frame_rate = frame_rate;
    *encoder = created;
    return 0;
}

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
) {
    if (!encoder || !encoder->component || !packets) {
        set_error(error_message, error_message_size, "AV1 encoder was used before create.");
        return -1;
    }
    if (!y_plane || !u_plane || !v_plane || presentation_time_units < 0 || duration_units == 0) {
        set_error(error_message, error_message_size, "Invalid AV1 input frame.");
        return -1;
    }

    const size_t expected_y_size = (size_t)encoder->width * (size_t)encoder->height;
    const size_t expected_chroma_size = (size_t)(encoder->width / 2) * (size_t)(encoder->height / 2);
    if (y_plane_size != expected_y_size || u_plane_size != expected_chroma_size || v_plane_size != expected_chroma_size) {
        set_error(error_message, error_message_size, "Invalid AV1 input plane sizes.");
        return -1;
    }

    packets->packets = NULL;
    packets->count = 0;

    EbSvtIOFormat input = {
        .luma = (uint8_t *)y_plane,
        .cb = (uint8_t *)u_plane,
        .cr = (uint8_t *)v_plane,
        .y_stride = (uint32_t)encoder->width,
        .cr_stride = (uint32_t)(encoder->width / 2),
        .cb_stride = (uint32_t)(encoder->width / 2),
    };
    EbBufferHeaderType header = {
        .size = sizeof(EbBufferHeaderType),
        .p_buffer = (uint8_t *)&input,
        .n_filled_len = (uint32_t)(y_plane_size + u_plane_size + v_plane_size),
        .pts = presentation_time_units,
        .pic_type = EB_AV1_INVALID_PICTURE,
        .flags = 0,
        .metadata = NULL,
    };

    EbErrorType status = svt_av1_enc_send_picture(encoder->component, &header);
    if (status != EB_ErrorNone) {
        set_error_code(error_message, error_message_size, "svt_av1_enc_send_picture", status);
        return -1;
    }

    return drain_packets(encoder, 0, packets, error_message, error_message_size);
}

int LuxelAV1EncoderFinish(
    LuxelAV1Encoder *encoder,
    LuxelAV1PacketList *packets,
    char *error_message,
    size_t error_message_size
) {
    if (!encoder || !encoder->component || !packets) {
        set_error(error_message, error_message_size, "AV1 encoder was finished before create.");
        return -1;
    }

    packets->packets = NULL;
    packets->count = 0;

    if (!encoder->sent_eos) {
        EbBufferHeaderType eos = {
            .size = sizeof(EbBufferHeaderType),
            .flags = EB_BUFFERFLAG_EOS,
            .pic_type = EB_AV1_INVALID_PICTURE,
        };
        EbErrorType status = svt_av1_enc_send_picture(encoder->component, &eos);
        if (status != EB_ErrorNone) {
            set_error_code(error_message, error_message_size, "svt_av1_enc_send_picture(EOS)", status);
            return -1;
        }
        encoder->sent_eos = true;
    }

    return drain_packets(encoder, 1, packets, error_message, error_message_size);
}

void LuxelAV1EncoderDestroy(LuxelAV1Encoder *encoder) {
    if (!encoder) {
        return;
    }
    if (encoder->component) {
        if (!encoder->deinitialized) {
            svt_av1_enc_deinit(encoder->component);
            encoder->deinitialized = true;
        }
        svt_av1_enc_deinit_handle(encoder->component);
    }
    free(encoder);
}

void LuxelAV1PacketListDestroy(LuxelAV1PacketList *packets) {
    if (!packets || !packets->packets) {
        return;
    }
    for (size_t index = 0; index < packets->count; index += 1) {
        free(packets->packets[index].data);
    }
    free(packets->packets);
    packets->packets = NULL;
    packets->count = 0;
}
