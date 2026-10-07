attribute vec3 centr;
                attribute vec2 textWeights;

                uniform float uShow;
                uniform float uHide;

                flat varying vec3 vCentr;

                ${globalUBO_default}
                ${falloff_default}
                ${slugvs_default}
                ${eases_default}

                float hash13(vec3 p3) {
                    p3  = fract(p3 * .1031);
                    p3 += dot(p3, p3.zyx + 31.32);
                    return fract((p3.x + p3.y) * p3.z);
                }

                vec2 hash23(vec3 p3) {
                    p3 = fract(p3 * vec3(.1031, .1030, .0973));
                    p3 += dot(p3, p3.yzx+33.33);
                    return fract((p3.xx+p3.yz)*p3.zy);
                }

                void main() {
                    vCentr = centr;
                    vec3 pos = SlugVS();

                    float seed = fract(hash13(centr));

                    // animation
                    if (uShow < 1.0 || uHide > 0.0) {
                        // show
                        float stepsShow = floor(3.0 + seed * 2.0);
                        float trShow = floor(falloff(textWeights.y, 0.0, 1.0, 0.1, uShow) * stepsShow) / stepsShow;
                        vTexCoord += vec2(0.0, 1.0) * (1.0 - trShow);

                        // hide
                        float stepsHide = floor(2.0 + seed * 2.0);
                        float trHide = 1.0 - floor(uHide * (stepsHide + 1.0)) / (stepsHide + 1.0);
                        pos -= centr;
                        pos *= trHide;
                        pos += centr;
                    }

                    // wiggle
                    float steppedTime = floor(time * 1.6 * mix(fract(seed), 0.8, 1.0) + seed * 15.3423) / 7.0;
                    vec2 offset = (hash23(centr + vec3(steppedTime, 0.0, 0.0)) * 2.0 - 1.0) * 0.5;
                    pos.xy += offset;

                    gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
                }
