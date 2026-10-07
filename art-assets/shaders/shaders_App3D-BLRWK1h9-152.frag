${globalUBO_default}
                ${fit_default}
                ${depth_default}
                ${bicubic_default}
                ${parabolas_default}
                ${sinenoise_default}
                ${eases_default}
                ${fog_default}

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec3 vLPos;
                varying vec4 vPos;

                uniform sampler2D tNoise;
                uniform sampler2D tNoise2;
                uniform sampler2D tNoise3;
                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColor3;
                uniform vec3 uColorWaves2;

                uniform vec2 uDepthRange;

                uniform mat4 uProjMat;
                uniform mat4 uWorldMat;

                uniform sampler2D tScene;
                uniform sampler2D tSceneInfo;

                uniform float uCameraNear;
                uniform float uCameraFar;

                vec4 getWave(float t) {

                    float w1 = sin(t) * 0.5 + 0.5;
                    float w2 = sin(t + 3.14159) * 0.5 + 0.5;
                    float looptime = fract(t / 6.283 + 3.14159 * 5.0);

                    float n1 = 1.0 - texture2D(tNoise2, vUv * vec2(1.5, 2.5) + vec2(w1 * 1.0, - w1 * 0.1)).r;
                    float n2 = texture2D(tNoise, vUv * vec2(2.0, 4.0) + vec2(w1 * 1.0, -t * 0.24)).r;
                    float n3 = texture2D(tNoise, vUv * vec2(2.0, 2.0) + vec2(w1 * 0.1, -t * 0.065)).r;

                    float og1 = vUv.x + w1;
                    og1 += n1 * 0.2 - 0.1;
                    float base1 = fract(og1);
                    base1 *= 1.0 - step(1.0, og1);

                    float foamfront1 = smoothstep(0.9, 1.0, base1);
                    float foamwide1 = base1 * n2 * smoothstep(0.0, 0.5, base1);
                    float rearfade = smoothstep(0.0, 0.3, vUv.x);
                    foamwide1 *= rearfade;
                    foamfront1 *= rearfade;

                    float value = foamfront1 + foamwide1;
                    value *= smoothstep(1.0, 0.3, looptime);

                    float alpha = base1;

                    value = step(0.45, value);

                    vec4 color = vec4(mix(mix(uColor1, uColor2, step(0.7, n3)), vec3(1.0), value), alpha);

                    return color;
                }

                float getWetSand(float t) {

                    float wetsand_w1 = sin(t) * 0.5 + 0.5;
                    float wetsand_looptime = fract(t / 6.283 + 3.14159 * 5.0 + 0.018);

                    float wetsand_og1 = vUv.x + wetsand_w1;
                    float wetsand_n1 = 1.0 - texture2D(tNoise2, vUv * vec2(1.5, 2.5) + vec2(wetsand_w1 * 1.0, -wetsand_w1 * 0.1)).r;
                    wetsand_og1 += wetsand_n1 * 0.2 - 0.1;
                    float wetsand_base1 = fract(wetsand_og1);
                    wetsand_base1 *= 1.0 - step(0.99, wetsand_og1);
                    wetsand_base1 *= 1.0 - wetsand_looptime;

                    return wetsand_base1;
                }

                void main() {
                    float t = time * 0.66;

                    vec4 wave = getWave(t);
                    float wetsand = getWetSand(t - 0.3);

                    vec4 wave2 = getWave(t + 3.14159);
                    float wetsand2 = getWetSand(t + 3.14159 - 0.3);

                    wave = max(wave, wave2);
                    wetsand = max(wetsand, wetsand2);

                    float wetsandmask = step(0.01, wetsand) - step(0.01, wave.a);
                    wetsandmask = max(0.0, wetsandmask);

                    vec3 color = mix(wave.rgb, uColor3, wetsandmask);

                    if (wave.a + wetsandmask < 0.01) discard;

                    // calc positions in world space
                    vec2 screenUv = gl_FragCoord.xy / resolution.xy;

                    float sceneDepth = 1.0 - texture2D(tSceneInfo, screenUv).r;
                    float waterSurfaceDepth = 0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5;

                    // calculate height and depth differences
                    vec3 sceneViewPos = getViewPosition(sceneDepth, screenUv, uCameraNear, uCameraFar, uProjMat);
                    vec3 sceneWorldPos = (uWorldMat * vec4(sceneViewPos, 1.0)).xyz;
                    float sceneDist = length(sceneViewPos);
                    float sceneHeight = length(sceneWorldPos);
                    vec3 waterViewPos = getViewPosition(waterSurfaceDepth, screenUv, uCameraNear, uCameraFar, uProjMat);
                    vec3 waterWorldPos = (uWorldMat * vec4(waterViewPos, 1.0)).xyz;
                    float waterDist = length(waterViewPos);
                    float waterHeight = length(waterWorldPos);

                    float viewDistDiff = sceneDist - waterDist;
                    float worldHeightDiff = waterHeight - sceneHeight;

                    float depthGradient = fit(viewDistDiff, 0.0, 2.5, 0.0, 1.0);

                    float outlinecontribution = 0.0;

                    // add scene color
                    float gradientScene = 1.0 - max(fit(worldHeightDiff, 0.0, 0.2, 0.0, 1.0), depthGradient);
                    float gradientSceneSmall = 1.0 - max(fit(worldHeightDiff, 0.0, 0.06, 0.0, 1.0), depthGradient);
                    color = mix(color, mix(color + color, color * color, wetsandmask), gradientScene * 0.5);
                    color = mix(color, mix(color + color, color * color, wetsandmask), pow(gradientSceneSmall, 5.0));
                    color = clamp(color, vec3(0.0), vec3(1.0));

                    // add character shadow
                    color = mix(color, color * (step(0.5, texture2D(tScene, screenUv).r) * 0.3 + 0.7), smoothstep(0.3, 0.65, vUv.x));

                    // float timeOffset = sinenoise1(vec3(vUv * 50.0, 0.0)) * 0.5 + 0.5;

                    // // calculate foam
                    // float foam = 0.0;
                    // float foamMargin = fit(worldHeightDiff, 0.0, 0.3, 1.0, 0.0);
                    // if (foamMargin > 0.0) {

                    //     // bands
                    //     float foamBands = foamMargin * 4.0 - time * 0.35 + timeOffset * 2.0;
                    //     foam = parabola(fract(foamBands), 5.0);

                    //     // add shapes
                    //     // float foamNoise = texture2D(tNoise, vUv * 15.0 - (time + floor(foamBands) * 50.342) * 0.001).r;
                    //     // foam *= foamMargin * foamNoise;
                    //     foam *= foamMargin;

                    //     // set threshold
                    //     foam = step(0.42, foam);

                    //     // limit it to places where the depth is visible
                    //     float foamVisibility = fit(viewDistDiff, 0.0, 1.0, 0.0, 1.0);
                    //     foam *= 1.0 - step(0.99, pow(foamVisibility, 2.0));
                    // }
                    // color = max(color, vec3(foam));

                    // add fog
                    addFog(color, vPos.z);


                    gl_FragColor = vec4(color, 1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5));
                }
