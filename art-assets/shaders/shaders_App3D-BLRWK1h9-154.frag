layout(location = 1) out highp vec4 gInfo;

                ${globalUBO_default}
                ${fog_default}

                uniform vec3 uColor;
                uniform sampler2D tNoise;
                uniform sampler2D tNoise2;

                varying float vRandom;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying vec2 vHighPrecisionZW;
                varying vec3 vWorldPos;
                varying vec4 vPos;
                varying float vFresnel;
                varying float vThickness;

                void main() {
                    float n1 = texture2D(tNoise, vUv2 * vec2(0.25, 1.0) - vec2(vRandom, time * 0.05)).r;
                    float n2 = 1.0 - texture2D(tNoise2, vec2(vUv2 * vec2(0.7, 1.5) - vec2(vRandom, time * 0.15))).r;
                    n2 -= n1 * 0.4;
                    n2 = pow(n2, 2.0);
                    // n += (1.0 - abs(vUv.x - 0.5) * 2.0) * 0.25;
                    // if (n < 0.5) discard;

                    float grad = 1.0 - abs(vUv.x - 0.5) * 2.0;
                    float mask = grad * n2;
                    // mask -= vUv.y * 0.15;
                    mask -= (sin(vUv.y * 2.0 - time + vRandom * 10.0) * 0.5 + 0.5) * 0.15;
                    mask *= smoothstep(0.0, 0.15, vUv2.y);
                    mask *= smoothstep(1.0, 0.5, vUv2.y);
                    if (mask < 0.05) discard;
                    vec3 color = vec3(1.0);

                    addFog(color, vPos.z);

                    gl_FragColor.rgb = color;
                    gl_FragColor.a = 0.35;

                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 0.0);
                }
