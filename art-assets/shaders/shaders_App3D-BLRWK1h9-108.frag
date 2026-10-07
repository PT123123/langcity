${globalUBO_default}
                ${aastep_default}
                ${fog_default}

                layout(location = 1) out highp vec4 gInfo;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying float vScaleFactor;
                varying vec3 vLocalPos;
                varying vec4 vPos;

                uniform sampler2D tNoise;
                uniform sampler2D tNoise2;
                uniform sampler2D tNoise3;
                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColor3;

                void main() {

                    vec3 off = vLocalPos * 0.025;

                    vec2 uv = vUv;
                    uv.y *= 0.08;

                    uv.y += time * 0.04;

                    float n1 = texture2D(tNoise, vec2(uv.x * (0.5 - vScaleFactor * 0.3) + time * 0.01, uv.y + vScaleFactor * 0.25)).r; // foam
                    float n2 = texture2D(tNoise2, vUv * vec2(0.5, 0.1) + vec2(off.x, time * 0.05)).g;
                    n2 -= texture2D(tNoise2, vUv * vec2(2.0 - vScaleFactor * 2.0, 0.15) + vec2(off.z, time * 0.031)).g;
                    float n3 = texture2D(tNoise2, vUv * vec2(0.5, 0.5 + vUv.y * 0.25) + vec2(-off.x, time * 0.3)).r;

                    float n4 = 1.0 - texture2D(tNoise3, vUv * vec2(0.5, 0.5) - vec2(time * 0.02 - off.z, time * 0.11)).r;
                    n4 = 1.0 - pow(1.0 - n4, 2.0);

                    float edgegrad = 1.0 - abs(vUv.x - 0.5) * 2.0;
                    edgegrad -= n3 * 0.2;

                    float edgemask = 1.0 - aastep(0.125 + vScaleFactor * 0.25, edgegrad);

                    // streaks
                    float streaks = 1.0 - abs(n1 - 0.5) * 2.0;
                    streaks = streaks * streaks * streaks;
                    streaks = aastep(0.5, streaks);

                    // foam near ground
                    float foam = vUv.y - n4 * 0.04;
                    float foammask = 1.0 - step(0.002, foam);

                    if (edgegrad < 0.05) discard;

                    // stylized specular shine
                    float shine1 = 1.0 - clamp(abs(vUv.y - 0.6) * 4.0, 0.0, 1.0);
                    shine1 = 1.0 - pow(1.0 - shine1, 2.0);
                    shine1 -= n2 * 0.06;
                    shine1 = aastep(0.97, shine1);

                    // another specular shine
                    float shine2 = 1.0 - clamp(abs(vUv.y - 0.3) * 4.0, 0.0, 1.0);
                    shine2 = 1.0 - pow(1.0 - shine2, 2.0);
                    shine2 -= n2 * 0.2;
                    shine2 = aastep(0.91, shine2 - 0.05);

                    // darker color near base of waterfall
                    float shadow = vUv.y - n2 * 0.25;
                    shadow = 1.0 - aastep(0.275, shadow);

                    // composite all effects together
                    vec3 color = uColor1;
                    color = mix(color, uColor3, max(shine1, shine2));
                    color = mix(color, uColor2, shadow);
                    color = mix(color, vec3(1.0), max(streaks, edgemask));
                    color = mix(color, vec3(1.0), foammask);

                    gl_FragColor = vec4(color, 1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5));
                    gInfo = vec4(1.0, vec2(0.0), 0.0);

                }
