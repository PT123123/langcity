${globalUBO_default}
                ${fit_default}

                uniform sampler2D tMap;
                uniform float uSmoothMargin;
                uniform vec3 uOutlineColor;
                uniform float uThreshold;

                varying vec2 vUv;

                const vec2 dirs[5] = vec2[5](vec2(0, 0), vec2(-1, 0), vec2(1, 0), vec2(0, -1), vec2(0, 1)); // center, left, right, bottom, top

                void main() {
                    float scale = 1.0; // important

                    vec2 offset = 1.0 / vec2(textureSize(tMap, 0)) * scale;
                    vec4 colors[5];

                    // keep track of alphas and minimum color value to skip computations or outlines entirely
                    float maxAlpha = 0.0;
                    float minColorValue = 0.0;
                    vec4 tcolor;

                    #pragma unroll_loop_start
                    for (int i = 0; i < 5; i++) {
                        tcolor = texture(tMap, vUv + offset * dirs[i]);
                        colors[i] = abs(tcolor);
                        maxAlpha = max(maxAlpha, colors[i].a);
                        minColorValue = min(minColorValue, min(tcolor.r, min(tcolor.g, tcolor.b)));
                    }
                    #pragma unroll_loop_end

                    // early out: no alpha changes
                    if (maxAlpha == 0.0) discard;

                    // no outline if color is negative and alpha is equal or lower than 1. pure black is not valid
                    if (minColorValue < 0.0 && maxAlpha <= 1.0) {
                        gl_FragColor = colors[0];
                        return;
                    }

                    vec3 centerColor = colors[0].rgb;
                    vec3 variationLeft = abs(colors[1].rgb - centerColor);
                    vec3 variationRight = abs(colors[2].rgb - centerColor);
                    vec3 variationBottom = abs(colors[3].rgb - centerColor);
                    vec3 variationTop = abs(colors[4].rgb - centerColor);

                    // clamp differences in alpha since values can range from 0 to 2, so the smoothing is normalized
                    float centerAlpha = colors[0].a;
                    float variationLeftAlpha = clamp(abs(colors[1].a - centerAlpha), 0.0, 1.0);
                    float variationRightAlpha = clamp(abs(colors[2].a - centerAlpha), 0.0, 1.0);
                    float variationBottomAlpha = clamp(abs(colors[3].a - centerAlpha), 0.0, 1.0);
                    float variationTopAlpha = clamp(abs(colors[4].a - centerAlpha), 0.0, 1.0);

                    vec4 delta;
                    delta.x = max(max(max(variationLeft.r, variationLeft.g), variationLeft.b), variationLeftAlpha);
                    delta.y = max(max(max(variationTop.r, variationTop.g), variationTop.b), variationTopAlpha);
                    delta.z = max(max(max(variationRight.r, variationRight.g), variationRight.b), variationRightAlpha);
                    delta.w = max(max(max(variationBottom.r, variationBottom.g), variationBottom.b), variationBottomAlpha);

                    vec2 maxDelta = max(delta.xy, delta.zw);
                    float maxDeltaValue = max(maxDelta.x, maxDelta.y);

                    vec3 color = mix(centerColor, uOutlineColor, smoothstep(uThreshold, uThreshold + uSmoothMargin, maxDeltaValue));

                    gl_FragColor = vec4(color, 1.0);
                }
