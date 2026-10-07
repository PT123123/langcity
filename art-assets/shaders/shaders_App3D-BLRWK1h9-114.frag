${globalUBO_default}
                ${triplanar_default}

                layout(location = 1) out highp vec4 gInfo;

                varying vec2 vHighPrecisionZW;
                varying vec3 vNormal;
                varying vec3 vMvPos;
                varying vec3 vPos;

                uniform sampler2D tCloudNoise;
                uniform vec3 uColor1;
                uniform float uShow;

                void main() {
                    float fresnel = dot(normalize(vNormal), normalize(vMvPos.xyz));
                    fresnel = abs(fresnel);

                    // main cloud shape
                    float noise = triplanar(tCloudNoise, vNormal, vPos, 0.015).x;
                    noise *= 1.0 - pow(1.0 - fresnel, 2.0);
                    noise *= uShow;

                    if (noise < 0.3) discard;

                    gl_FragColor = vec4(uColor1, 0.434532);
                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 0.0);
                }
