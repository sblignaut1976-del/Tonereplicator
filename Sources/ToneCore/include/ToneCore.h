#ifndef TONE_CORE_H
#define TONE_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define TR_CANONICAL_RATE 44100
typedef struct TRMeter TRMeter;
typedef struct TRSampleQueue TRSampleQueue;
/* Create/destroy only on the control thread, after the callback has stopped. */
TRMeter *tr_meter_create(void);
void tr_meter_destroy(TRMeter *meter);
int tr_rate_supported(double rate);
int tr_route_valid(uint32_t channel, uint32_t available);
/* One callback writer, any telemetry readers. Nonfinite samples count as invalid. */
void tr_meter_process(TRMeter *meter, const float *samples, uint32_t count);
float tr_meter_peak(const TRMeter *meter);
float tr_meter_rms(const TRMeter *meter);
uint64_t tr_meter_frames(const TRMeter *meter);
uint64_t tr_meter_invalid(const TRMeter *meter);
/* Exactly one producer and one consumer; capacity is fixed at construction. */
TRSampleQueue *tr_queue_create(uint32_t capacity);
void tr_queue_destroy(TRSampleQueue *queue);
uint32_t tr_queue_push(TRSampleQueue *queue, const float *samples, uint32_t count);
uint32_t tr_queue_pop(TRSampleQueue *queue, float *samples, uint32_t count);
uint64_t tr_queue_dropped(const TRSampleQueue *queue);
#ifdef __cplusplus
}
#endif
#endif
