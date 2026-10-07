${globalUBO_default}
                ${aastep_default}
                ${fog_default}

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec4 vPos;

                uniform sampler2D tNoise;
                uniform sampler2D tNoise2;
                uniform sampler2D tNoise3;
                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColor3;

                void main() {

                    vec2 uv = vUv * vec2(1.0, 5.0);
                    uv.x = pow(uv.x, 2.0);

                    // animated texture
                    float mask1 = texture2D(tNoise, uv + vec2(-time * 0.2, 0.0)).r;

                    // concentric rings that animate outwards
                    float concentric = sin(uv.x * 25.0 - time * 5.0) * 0.5 + 0.5;

                    // foam pattern that animates outwards
                    float foam = mask1 * 0.65;
                    foam += 0.3 * (pow(concentric, 20.0));
                    foam += pow(1.0 - vUv.x, 3.0);
                    foam *= 1.0 - pow(smoothstep(0.2, 1.0, vUv.x), 3.0);

                    float alpha = step(0.5, foam);
                    if (alpha < 0.5) discard;

                    vec3 color = vec3(1.0);
                    addFog(color, vPos.z);

                    gl_FragColor = vec4(color, 1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5));
                }
