attribute vec3 centr;
            attribute vec2 textWeights;

            uniform float uAnimationProgress;

            uniform vec2 uSize;
            uniform vec2 uMargins;
            uniform float uAlpha;

            flat varying vec3 vCentr;
            varying vec2 vHighPrecisionZW;

            ${falloff_default}
            ${matrixutils_default}
            ${globalUBO_default}
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
                float show = uAnimationProgress;
                float hide = 1.0 - uAlpha;

                if (show < 1.0 || hide > 0.0) {
                    // show
                    float stepsShow = floor(3.0 + seed * 2.0);
                    float trShow = floor(falloff(textWeights.y, 0.0, 1.0, 0.1, show) * stepsShow) / stepsShow;
                    vTexCoord += vec2(0.0, 1.0) * (1.0 - trShow);

                    // hide
                    float stepsHide = floor(1.0 + seed * 2.0);
                    float trHide = 1.0 - floor(hide * (stepsHide + 1.0)) / (stepsHide + 1.0);
                    pos -= centr;
                    pos *= trHide;
                    pos += centr;
                }

                // wiggle
                float steppedTime = floor(time * 1.6 * mix(fract(seed), 0.8, 1.0) + seed * 15.3423) / 7.0;
                vec2 offset = (hash23(centr + vec3(steppedTime, 0.0, 0.0)) * 2.0 - 1.0) * 0.0025;
                pos.xy += offset;

                // offset text to center it
                pos.x -= uSize.x * 0.5;
                pos.y -= 0.055; // compensate for pointer
                pos.y += uSize.y + uMargins.y; // compensate for font size and bottom margin

                gl_Position = projectionMatrix * viewMatrix * billboardModelMatrix() * vec4(pos, 1.0);
                vHighPrecisionZW = gl_Position.zw;
            }
