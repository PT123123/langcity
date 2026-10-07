layout(location = 1) out highp vec4 gInfo;

            ${slugfs_default}
            ${sinenoise_default}
            ${globalUBO_default}
            ${parabolas_default}
            ${fit_default}

            varying vec2 vUv;
            varying vec3 vLocalPos;
            varying vec2 vHighPrecisionZW;

            uniform sampler2D tCurve;
            uniform usampler2D tBand;
            uniform vec3 uColor1;
            uniform vec3 uColor2;
            uniform float uRand;

            uniform int uActive;

            void main() {
                vec4 color = RenderSlug(tCurve, tBand, vTexCoord, vColor, vBanding, vGlyph);
                if (color.w * vColor.w < 0.001) discard;

                float onlineContribution = 1.0;
                float rand = uRand;

                if (uActive == 1) {
                    // draw the 3 dots
                    vec2 uv = vUv;

                    uv -= 0.5;
                    uv *= vec2(1.217, 1.0); // fix aspect

                    // add noise in the outline only if active
                    float noise = sinenoise1(vec3(vLocalPos.xy * 15.0 + uRand * vec2(2.43, 4.453), uRand * 15.342));
                    onlineContribution = step(-0.3, noise);

                    // dots
                    const float offsetDist = 0.285;
                    const vec2 offsets[3] = vec2[3](vec2(0.0, 0.0), vec2(-offsetDist, 0.0), vec2(offsetDist, 0.0));
                    vec2 offset;
                    vec2 pos1;
                    float dist1;
                    float cut1;
                    #pragma unroll_loop_start
                    for (int i = 0; i < 3; i++) {
                        offset = offsets[i];
                        pos1 = uv + offset;
                        pos1.y -= parabola(fit(fract(time * 0.5 + uRand + offset.x * 0.15), 0.7, 1.0, 0.0, 1.0), 3.0) * 0.15;
                        dist1 = length(pos1);
                        cut1 = step(0.085, dist1);
                        color.rgb = mix(uColor2, color.rgb, cut1);
                        rand = mix(fract(rand + 2.4235), rand, cut1);
                        onlineContribution = mix(1.0, onlineContribution, cut1);
                    }
                    #pragma unroll_loop_end
                }

                gl_FragColor = vec4(color.rgb, rand);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), onlineContribution);
            }
