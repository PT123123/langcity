${globalUBO_default}
                ${aastep_default}
                ${fog_default}

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying float vExtraFoam;
                varying vec4 vPos;

                uniform sampler2D tNoise;
                uniform sampler2D tNoise2;
                uniform sampler2D tNoise3;
                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColor3;

                void main() {

                    // vec2 uv = vUv * vec2(1.0, 5.0);
                    // uv.x = pow(uv.x, 2.0);

                    float foam = texture2D(tNoise, vUv * vec2(0.5, 2.0) + vec2(0.5, time * 0.15)).r;
                    float foam2 = texture2D(tNoise, vUv * vec2(0.5, 2.0) * 2.0 + vec2(0.0, time * 0.13)).r;
                    float edges = smoothstep(0.3, 0.0, vUv.x) + smoothstep(0.8, 1.0, vUv.x);

                    // // concentric rings that animate outwards
                    // float concentric = sin(uv.x * 25.0 - time * 5.0) * 0.5 + 0.5;

                    // // foam pattern that animates outwards
                    // float foam = mask1 * 0.65;
                    // foam += 0.3 * (pow(concentric, 20.0));
                    // foam += pow(1.0 - vUv.x, 3.0);
                    // foam *= 1.0 - pow(smoothstep(0.2, 1.0, vUv.x), 3.0);

                    // float alpha = step(0.5, foam);
                    // if (alpha < 0.5) discard;

                    float value = max(foam, edges);
                    value = max(value, smoothstep(0.2, 0.0, vUv.y) - foam2 * 0.1 + vExtraFoam * foam2 * 1.5);
                    value = step(0.7, value);

                    // composite all effects together
                    vec3 color = uColor1;
                    color = mix(uColor1, uColor2, step(0.4, smoothstep(0.425, 0.6, vUv.y) - foam2 * 0.1));
                    color = mix(color, vec3(1.0), value);

                    float n2 = texture2D(tNoise2, vUv * vec2(0.55, 1.0) + vec2(0.0, time * 0.07)).g;
                    float alpha = smoothstep(0.0, 0.05, vUv.y) - foam2 * 0.4;
                    if (alpha < 0.05) discard;

                    addFog(color, vPos.z);

                    gl_FragColor = vec4(color, 1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5));
                }
