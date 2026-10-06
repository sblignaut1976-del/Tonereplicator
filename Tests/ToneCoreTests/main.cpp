#include "ToneCore.h"
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>
#include <vector>

static unsigned checks = 0;
static void check(bool result, const char *name) {
    if (!result) throw std::runtime_error(name);
    ++checks; std::cout << "PASS " << name << '\n';
}
int main() {
    try {
        check(tr_rate_supported(44100) && !tr_rate_supported(48000) &&
              !tr_rate_supported(std::numeric_limits<double>::quiet_NaN()), "canonical rate rejects unsupported/nonfinite rates");
        check(tr_route_valid(1,2) && !tr_route_valid(2,2) && !tr_route_valid(0,0), "channel bounds");
        auto *m = tr_meter_create();
        check(m && tr_meter_frames(m)==0 && tr_meter_peak(m)==0, "meter initialization");
        std::vector<float> sine(44100);
        for (unsigned i=0; i<sine.size(); ++i) sine[i] = 0.5f * std::sin(2 * 3.141592653589793 * 1000 * i / 44100);
        tr_meter_process(m,sine.data(),uint32_t(sine.size()));
        check(std::abs(tr_meter_rms(m)-0.5/std::sqrt(2.0))<1e-6 &&
              std::abs(tr_meter_peak(m)-0.5)<1e-5 && tr_meter_frames(m)==44100, "known sine peak/RMS and frame count");
        float bad[] = {std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN(), 2.0f};
        tr_meter_process(m,bad,3);
        check(tr_meter_invalid(m)==2 && tr_meter_peak(m)==2 && std::isfinite(tr_meter_rms(m)), "invalid samples counted; clipping preserved");
        tr_meter_process(m,nullptr,100);
        check(tr_meter_frames(m)==44103, "missing buffers leave counters unchanged");
        tr_meter_destroy(m);
        check(tr_queue_create(0)==nullptr, "zero queue rejected");
        auto *q = tr_queue_create(4); float in[]={1,2,3,4,5}, out[5]={};
        check(tr_queue_push(q,in,5)==4 && tr_queue_dropped(q)==1, "full queue drops new frames without blocking");
        check(tr_queue_pop(q,out,3)==3 && out[0]==1 && out[2]==3, "queue preserves order");
        tr_queue_push(q,in,3);
        check(tr_queue_pop(q,out,5)==4 && out[0]==4 && out[1]==1 && out[3]==3, "queue wraparound");
        tr_queue_destroy(q);
        q=tr_queue_create(128);
        constexpr unsigned total=200000;
        std::thread producer([&] {
            for (unsigned i=0;i<total;) {
                float value=float(i);
                if (tr_queue_push(q,&value,1)) ++i;
                else std::this_thread::yield();
            }
        });
        bool ordered=true;
        for (unsigned i=0;i<total;) {
            float value=-1;
            if (tr_queue_pop(q,&value,1)) { ordered &= value==float(i); ++i; }
            else std::this_thread::yield();
        }
        producer.join(); tr_queue_destroy(q);
        check(ordered,"concurrent producer/consumer: 200,000 frames in order");
        std::cout << checks << " checks passed\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
}
