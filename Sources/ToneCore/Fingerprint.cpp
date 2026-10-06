#include "ToneCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>

namespace {
constexpr unsigned size=2048, hop=1024;
constexpr double pi=3.1415926535897932384626433832795;
void fft(std::array<std::complex<double>, size>& a) {
    for (unsigned i=1,j=0;i<size;++i) {
        unsigned bit=size>>1;
        for (;j&bit;bit>>=1) j^=bit;
        j^=bit;
        if (i<j) std::swap(a[i],a[j]);
    }
    for (unsigned len=2;len<=size;len<<=1) {
        const auto step=std::polar(1.0,-2*pi/len);
        for (unsigned offset=0;offset<size;offset+=len) {
            std::complex<double> w(1,0);
            for (unsigned j=0;j<len/2;++j) {
                const auto u=a[offset+j],v=a[offset+j+len/2]*w;
                a[offset+j]=u+v; a[offset+j+len/2]=u-v; w*=step;
            }
        }
    }
}
}
extern "C" {
double tr_band_edge(uint32_t edge) {
    return edge<=TR_FINGERPRINT_BANDS ? 40*std::pow(500.0,double(edge)/TR_FINGERPRINT_BANDS) : 0;
}
int tr_fingerprint(const float *samples,uint32_t count,double rate,TRFingerprint *out) {
    if (!samples || !out || count<size || !tr_rate_supported(rate)) return 0;
    *out=TRFingerprint{}; out->frames=count;
    double energy=0,total=0;
    for (uint32_t i=0;i<count;++i) {
        if (!std::isfinite(samples[i])) { ++out->invalid; continue; }
        const double value=samples[i];
        if (std::abs(value)>=1) ++out->clipped;
        energy+=value*value; total+=value; out->peak=std::max(out->peak,std::abs(value));
    }
    out->rms=std::sqrt(energy/count); out->dc=total/count;
    std::array<double,size> window{};
    double windowEnergy=0;
    for (unsigned i=0;i<size;++i) {
        window[i]=0.5*(1-std::cos(2*pi*i/(size-1)));
        windowEnergy+=window[i]*window[i];
    }
    std::array<double,TR_FINGERPRINT_BANDS> powers{};
    std::array<std::complex<double>,size> spectrum{};
    for (uint32_t offset=0;offset<=count-size;offset+=hop) {
        for (unsigned i=0;i<size;++i) {
            const double value=std::isfinite(samples[offset+i]) ? samples[offset+i] : 0;
            spectrum[i]=value*window[i];
        }
        fft(spectrum); ++out->windows;
        for (unsigned bin=1;bin<=size/2;++bin) {
            const double frequency=rate*bin/size;
            if (frequency<40 || frequency>=20000) continue;
            const auto band=unsigned(std::log(frequency/40)/std::log(500.0)*TR_FINGERPRINT_BANDS);
            if (band<TR_FINGERPRINT_BANDS) {
                const double oneSided=bin==size/2 ? 1 : 2;
                powers[band]+=oneSided*std::norm(spectrum[bin])/(size*windowEnergy);
            }
        }
    }
    for (unsigned band=0;band<TR_FINGERPRINT_BANDS;++band)
        out->band_db[band]=10*std::log10(std::max(1e-12,powers[band]/out->windows));
    return 1;
}
}
