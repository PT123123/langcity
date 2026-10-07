#include <clipping_planes_pars_fragment>
            varying vec3 wPos;
            uniform float uShowChars;

            float sphereFade(vec3 p, float size, float amount) {
                float h = size * 0.5;
                return clamp(1.0 - step(amount * 1.85, length(mod(p, size) - h) / h), 0.0, 1.0);
            }
