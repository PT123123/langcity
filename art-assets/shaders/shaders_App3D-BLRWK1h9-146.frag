varying vec4 vMvPos;
                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;

                uniform vec3 uColor1;
                uniform vec3 uColor2;
                uniform vec3 uColorWaves1;
                uniform vec3 uColorWaves2;
                uniform vec2 uDepthRange;

                uniform sampler2D tNoise;

                uniform mat4 uProjMat;
                uniform mat4 uWorldMat;

                uniform sampler2D tScene;
                uniform sampler2D tSceneInfo;

                uniform float uCameraNear;
                uniform float uCameraFar;

                ${globalUBO_default}
                ${fit_default}
                ${depth_default}
                ${bicubic_default}
                ${parabolas_default}
                ${sinenoise_default}
                ${eases_default}
                ${fog_default}

                void main() {
                    // calc positions in world space
                    vec2 uv = gl_FragCoord.xy / resolution.xy;

                    vec2 meshUV = vUv * 1.25;

                    // get depths. sample bicubic on scene info to get a more defined depth
                    float sceneDepth = 1.0 - textureBicubic(tSceneInfo, uv).r;
                    float waterSurfaceDepth = 0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5;

                    // calculate height and depth differences
                    vec3 sceneViewPos = getViewPosition(sceneDepth, uv, uCameraNear, uCameraFar, uProjMat);
                    vec3 sceneWorldPos = (uWorldMat * vec4(sceneViewPos, 1.0)).xyz;
                    float sceneDist = length(sceneViewPos);
                    float sceneHeight = length(sceneWorldPos);
                    vec3 waterViewPos = getViewPosition(waterSurfaceDepth, uv, uCameraNear, uCameraFar, uProjMat);
                    vec3 waterWorldPos = (uWorldMat * vec4(waterViewPos, 1.0)).xyz;
                    float waterDist = length(waterViewPos);
                    float waterHeight = length(waterWorldPos);

                    float viewDistDiff = sceneDist - waterDist;
                    float worldHeightDiff = waterHeight - sceneHeight;

                    float depthGradient = fit(viewDistDiff, 0.0, 2.5, 0.0, 1.0);

                    float timeOffset = sinenoise1(vec3(meshUV * 50.0, 0.0)) * 0.5 + 0.5;

                    // calculate foam
                    float foam = 0.0;
                    float foamMargin = fit(worldHeightDiff, 0.0, 0.3, 1.0, 0.0);
                    if (foamMargin > 0.0) {

                        // bands
                        float foamBands = foamMargin * 4.0 - time * 0.35 + timeOffset * 2.0;
                        foam = parabola(fract(foamBands), 5.0);

                        // add shapes
                        float foamNoise = texture2D(tNoise, meshUV * 15.0 - (time + floor(foamBands) * 50.342) * 0.001).r;
                        foam *= foamMargin * foamNoise;

                        // set threshold
                        foam = step(0.42, foam);

                        // limit it to places where the depth is visible
                        float foamVisibility = fit(viewDistDiff, 0.0, 1.0, 0.0, 1.0);
                        foam *= 1.0 - step(0.99, pow(foamVisibility, 2.0));
                    }

                    float seaTime = time + timeOffset * 10.0;

                    // calculate water color
                    vec2 offsetSea1 = vec2(cos(seaTime * 1.0 + 3.432), sin(seaTime * 2.0 + 3.234)) * 0.01;
                    float noiseSea1 = texture2D(tNoise, meshUV * 8.0 - seaTime * 0.01 + offsetSea1).r;
                    vec2 offsetSea2 = vec2(sin(seaTime * 1.5 + 6.54353), cos(seaTime * 0.5 + 43.342)) * 0.0085;
                    float noiseSea2 = texture2D(tNoise, meshUV * 10.0 + 34.54 + seaTime * 0.015 + offsetSea2).r;
                    float noiseSea = noiseSea1 * noiseSea2;

                    float wavesN = step(0.1, pow(noiseSea, 2.0));
                    vec3 seaColor = mix(uColorWaves1, uColor2, wavesN);

                    vec2 offsetSea3 = vec2(sin(seaTime * 2.0 + 12.435), cos(seaTime * 2.75 + 34.3)) * 0.011;
                    float noiseSea3 = texture2D(tNoise, meshUV * 20.0 - seaTime * 0.01 + offsetSea3 - 3.525).r;
                    vec2 offsetSea4 = vec2(cos(seaTime * 1.25 + 3.345), sin(seaTime * 2.5 + 97.798)) * 0.0095;
                    float noiseSea4 = texture2D(tNoise, meshUV * 10.0 + 4.5434 + seaTime * 0.02 + offsetSea4 + 2.34).r;
                    float additionaNoiseSea = noiseSea3 * noiseSea4;

                    float wavesN2 = step(0.45, additionaNoiseSea);
                    seaColor = mix(seaColor, uColorWaves2, wavesN2);

                    // shore water color
                    float colorShore = max(fit(worldHeightDiff, 0.0, 0.15, 0.0, 1.0), depthGradient);
                    vec3 colorWater = mix(uColor1, seaColor, colorShore);

                    // add scene color
                    float gradientScene = 1.0 - max(fit(worldHeightDiff, 0.0, 0.75, 0.0, 1.0), depthGradient);
                    colorWater = mix(colorWater, uColorWaves2, gradientScene * 0.1);

                    // add foam
                    colorWater = mix(colorWater, vec3(1.0), foam);

                    addFog(colorWater, vMvPos.z);

                    gl_FragColor = vec4(colorWater, 1.0 - waterSurfaceDepth);
                }
