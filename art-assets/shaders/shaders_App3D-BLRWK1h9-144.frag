${globalUBO_default}

                layout(location = 1) out highp vec4 gInfo;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                uniform sampler2D tCloudNoise;
                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColor3;

                void main() {
                    vec2 screenUv = gl_FragCoord.xy / resolution;

                    float t = time * 0.0005;

                    vec2 uv = vUv * 1.0;

                    // main cloud shape
                    float noise = texture2D(tCloudNoise, uv * vec2(1.0, 2.0) + vec2(t)).r;
                    noise *= texture2D(tCloudNoise, uv * vec2(1.0, 2.0)).r;

                    // hide weirdness at poles
                    noise *= smoothstep(0.1, 0.2, 1.0 - abs(vUv.y - 0.5) * 2.0);

                    // if (noise < 0.15) discard;

                    float blend = step(0.27, noise);
                    float id = mix(0.01, 1.0, blend);
                    vec3 cloudColor = mix(uColor3, uColor2, screenUv.y);
                    vec3 color = mix(uColor1, cloudColor, blend);

                    gl_FragColor = vec4(color, id);
                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 1.0);
                }
