layout(location = 1) out highp vec4 gInfo;

                uniform vec2 uSize;
                uniform vec3 uColor;

                varying vec2 vUv;
                flat varying float vPointer;
                varying vec2 vHighPrecisionZW;

                float sdRoundedBox(vec2 p, vec2 b, float r) {
                    vec2 q = abs(p) - b + r;
                    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
                }

                void main() {
                    if (vPointer < 0.5) {
                        vec2 aspectMult = mix(vec2(uSize.x / uSize.y, 1.0), vec2(1.0, uSize.y / uSize.x), step(uSize.x, uSize.y));
                        float shape = sdRoundedBox((vUv - 0.5) * aspectMult, vec2(0.5) * aspectMult, 0.1 / min(uSize.x, uSize.y));
                        if (shape > 0.001) discard;
                    }

                    gl_FragColor = vec4(uColor, 0.0);
                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec3(0.0));
                }
