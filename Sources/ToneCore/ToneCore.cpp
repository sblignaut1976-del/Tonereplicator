#include "ToneCore.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>
#include <vector>

static_assert(std::atomic<float>::is_always_lock_free, "Real-time meter requires lock-free float");
static_assert(std::atomic<uint64_t>::is_always_lock_free, "Real-time counters require lock-free uint64");
struct TRMeter {
    std::atomic<float> peak{0}, rms{0};
    std::atomic<uint64_t> frames{0}, invalid{0};
};
struct TRSampleQueue {
    explicit TRSampleQueue(uint32_t n) : buffer(n) {}
    std::vector<float> buffer;
    alignas(64) std::atomic<uint64_t> write{0};
    alignas(64) std::atomic<uint64_t> read{0};
    std::atomic<uint64_t> dropped{0};
};
extern "C" {
TRMeter *tr_meter_create() { return new (std::nothrow) TRMeter; }
void tr_meter_destroy(TRMeter *m) { delete m; }
int tr_rate_supported(double r) { return std::isfinite(r) && r == TR_CANONICAL_RATE; }
int tr_route_valid(uint32_t c, uint32_t n) { return c < n; }
void tr_meter_process(TRMeter *m, const float *s, uint32_t n) {
    if (!m || !s || !n) return;
    float peak = 0;
    double energy = 0;
    uint64_t invalid = 0;
    for (uint32_t i = 0; i < n; ++i) {
        if (!std::isfinite(s[i])) { ++invalid; continue; }
        peak = std::max(peak, std::abs(s[i]));
        energy += double(s[i]) * double(s[i]);
    }
    m->peak.store(peak, std::memory_order_relaxed);
    m->rms.store(float(std::sqrt(energy / n)), std::memory_order_relaxed);
    m->invalid.fetch_add(invalid, std::memory_order_relaxed);
    m->frames.fetch_add(n, std::memory_order_release);
}
float tr_meter_peak(const TRMeter *m) { return m ? m->peak.load() : 0; }
float tr_meter_rms(const TRMeter *m) { return m ? m->rms.load() : 0; }
uint64_t tr_meter_frames(const TRMeter *m) { return m ? m->frames.load() : 0; }
uint64_t tr_meter_invalid(const TRMeter *m) { return m ? m->invalid.load() : 0; }
TRSampleQueue *tr_queue_create(uint32_t n) {
    if (!n) return nullptr;
    try { return new TRSampleQueue(n); } catch (...) { return nullptr; }
}
void tr_queue_destroy(TRSampleQueue *q) { delete q; }
uint32_t tr_queue_push(TRSampleQueue *q, const float *s, uint32_t n) {
    if (!q || !s) return 0;
    const auto w = q->write.load(std::memory_order_relaxed);
    const auto r = q->read.load(std::memory_order_acquire);
    const auto take = uint32_t(std::min<uint64_t>(n, q->buffer.size() - (w-r)));
    for (uint32_t i=0; i<take; ++i) q->buffer[(w+i)%q->buffer.size()] = s[i];
    q->write.store(w+take, std::memory_order_release);
    q->dropped.fetch_add(n-take, std::memory_order_relaxed);
    return take;
}
uint32_t tr_queue_pop(TRSampleQueue *q, float *s, uint32_t n) {
    if (!q || !s) return 0;
    const auto r = q->read.load(std::memory_order_relaxed);
    const auto w = q->write.load(std::memory_order_acquire);
    const auto take = uint32_t(std::min<uint64_t>(n, w-r));
    for (uint32_t i=0; i<take; ++i) s[i] = q->buffer[(r+i)%q->buffer.size()];
    q->read.store(r+take, std::memory_order_release);
    return take;
}
uint64_t tr_queue_dropped(const TRSampleQueue *q) { return q ? q->dropped.load() : 0; }
}
