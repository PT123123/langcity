layout(location = 1) out highp vec4 gInfo;

                uniform sampler2D tMap;
                uniform vec3 uColor;
                uniform float uFadeDistance;
                uniform float uShow;

                ${msdf_default}

                varying vec2 vUv;
                varying vec3 vPos;
                varying vec3 wPos;
                varying vec2 vHighPrecisionZW;
                varying float vDist;

                float sphereFade(vec3 p, float size, float amount) {
                    float h = size * 0.5;
                    return clamp(1.0 - step(amount * 1.85, length(mod(p, size) - h) / h), 0.0, 1.0);
                }

                void main() {
                    float alpha = msdfOpaque(tMap, vUv);
                    alpha *= sphereFade(wPos, 0.1, smoothstep(uFadeDistance, uFadeDistance * 0.8, vDist) * uShow);

                    if (alpha == 0.0) discard;

                    gl_FragColor = vec4(uColor, 0.0);
                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec3(0.0));
                }
