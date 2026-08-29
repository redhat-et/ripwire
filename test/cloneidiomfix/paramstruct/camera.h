#pragma once
// A param-struct initializer chain: declare, assign every field, return.
namespace optics
{

struct CameraParams
{
    float fov;
    float nearPlane;
    float farPlane;
    float exposure;
    float tint;
    float gamma;
    int   samples;
    bool  ortho;
};

inline CameraParams defaultCameraParams()
{
    CameraParams p;
    p.fov       = 60.0f;
    p.nearPlane = 0.1f;
    p.farPlane  = 900.0f;
    p.exposure  = 1.0f;
    p.tint      = 0.0f;
    p.gamma     = 2.2f;
    p.samples   = 4;
    p.ortho     = false;
    return p;
}

}   // namespace optics
