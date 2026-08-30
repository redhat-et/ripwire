#pragma once
// The same initializer-chain idiom in an unrelated domain, sharing no non-keyword identifier.
namespace audio
{

struct MixerParams
{
    float gain;
    float pan;
    float wet;
    float dry;
    float trim;
    float slew;
    int   rate;
    bool  mono;
};

inline MixerParams defaultMixerParams()
{
    MixerParams m;
    m.gain = 0.8f;
    m.pan  = 0.0f;
    m.wet  = 0.35f;
    m.dry  = 0.65f;
    m.trim = 1.0f;
    m.slew = 0.02f;
    m.rate = 48000;
    m.mono = false;
    return m;
}

}   // namespace audio
