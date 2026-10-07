layout(location = 1) out highp vec4 gInfo;

                ${globalUBO_default}
                ${fog_default}

                uniform vec3 uColor;
                uniform sampler2D tNoise;

                varying float vRandom;
                varying vec2 vUv;
                varying vec4 vPos;
                varying vec2 vHighPrecisionZW;

                void main() {

                    float n = texture2D(tNoise, vec2(0.5 + vRandom, vUv.y * 0.02)).r;
                    if (n < 0.4) discard;

                    vec3 color = uColor;

                    gl_FragColor = vec4(color, 1.0);
                    gInfo = vec4(1.0, vec2(0.0), 0.0);
                }
