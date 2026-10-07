layout(location = 1) out highp vec4 gInfo;

                        ${encoding_default}

                        varying vec2 vUv;
                        flat varying float vScale;
                        flat varying float vRand;
                        varying vec2 vHighPrecisionZW;

                        void main() {
                            if (vScale < 0.001) discard;

                            gl_FragColor = vec4(vec3(1.0), vRand);
                            gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 1.0);
                        }
