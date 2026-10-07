uniform sampler2D tCurve;
                uniform usampler2D tBand;

                flat varying vec3 vCentr;

                ${globalUBO_default}
                ${slugfs_default}
                ${transformUV_default}

                void main() {
                    // animation

                    vec2 uv = vTexCoord;
                    vec4 color = RenderSlug(tCurve, tBand, uv, vColor, vBanding, vGlyph);

                    // skip outline
                    gl_FragColor = vec4(-color.xyz, color.w * vColor.w);
                }
