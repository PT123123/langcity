uniform sampler2D tCurve;
                uniform usampler2D tBand;
                uniform sampler2D tNoise;
                uniform float uSeed;

                flat varying vec3 vCentr;

                ${globalUBO_default}
                ${slugfs_default}
                ${transformUV_default}

                void main() {
                    // animation
                    float seed = uSeed + vCentr.x;

                    vec2 uv = vTexCoord;

                    float steppedTime = floor(time * 7.0 * 0.45 * mix(fract(seed), 0.8, 1.0) + seed * 15.3423) / 7.0;
                    vec2 noiseUv = rotateUV(uv * 0.15, steppedTime);
                    vec2 n0 = texture(tNoise, noiseUv).rg * 2.0 - 1.0;
                    uv += n0 * 0.02;

                    vec4 color = RenderSlug(tCurve, tBand, uv, vColor, vBanding, vGlyph);

                    if (color.w * vColor.w < 0.0001) discard;

                    gl_FragColor = vec4(color.xyz, 1.0);
                }
