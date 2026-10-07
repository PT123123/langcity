#include <packing>
                varying vec2 vHighPrecisionZW;
                void main() {
                    float fragCoordZ = 0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5;
                    gl_FragColor = packDepthToRGBA( fragCoordZ );
                }
