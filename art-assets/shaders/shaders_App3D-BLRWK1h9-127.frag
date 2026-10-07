layout(location = 1) out highp vec4 gInfo;

                    ${encoding_default}

                    uniform sampler2D tNoise;
                    uniform vec3 uColor;

                    flat varying float vScale;
                    flat varying float vRand;
                    varying vec2 vHighPrecisionZW;

                    void main() {
                        vec2 uv = 2.0 * gl_PointCoord.xy - 1.0;
                        float dist = length(uv);
                        float alpha = smoothstep(0.7, 0.0, dist);

                        float noise = texture(tNoise, (uv + vRand * 6.43563) * 0.3).r;
                        float mask = alpha * noise;

                        if (mask < 0.4) discard;

                        gl_FragColor = vec4(uColor, vRand);
                        gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 1.0);
                    }
