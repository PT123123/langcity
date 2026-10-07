attribute vec3 centr;
            attribute vec2 textWeights;

            uniform float uShow;
            uniform float uHide;
            uniform float uHover;

            flat varying vec3 vCentr;
            varying vec2 vHighPrecisionZW;

            ${globalUBO_default}
            ${falloff_default}
            ${slugvs_default}
            ${eases_default}
            ${rotate_default}

            vec3 hash31(float p) {
                vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
                p3 += dot(p3, p3.yzx+33.33);
                return fract((p3.xxy+p3.yzz)*p3.zyx);
            }

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
                    float trShow = floor(falloff(textWeights.y, 0.0, 1.0, 1.5, uShow) * stepsShow) / stepsShow;
                    float trHide = floor(falloff(textWeights.y, 0.0, 1.0, 1.5, uHide) * stepsShow) / stepsShow;
                    vTexCoord += vec2(0.0, 1.0) * (1.0 - trShow);
                    vTexCoord -= vec2(0.0, 1.0) * trHide;
                }

                // random stepped rotation animation
                float t = floor(time * 3.0);
                vec3 axis = normalize(hash31(t) * 2.0 - 1.0);
                float angle = 0.02;

                vec4 pos2 = vec4(pos, 1.0);
                pos2.xyz *= 1.0 - 0.05 * uHover;
                pos2 = rotation3D(axis, angle) * pos2;

                gl_Position = projectionMatrix * modelViewMatrix * pos2;
                vHighPrecisionZW = gl_Position.zw;
            }
