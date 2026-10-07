uniform sampler2D tCurve;
                uniform usampler2D tBand;

                ${slugfs_default}

                varying vec2 vUv;

                void main() {
                    vec4 color = RenderSlug(tCurve, tBand, vTexCoord, vColor, vBanding, vGlyph);

                    if (color.w * vColor.w < 0.001) discard;

                    gl_FragColor = vec4(color.rgb, 1.0);
                }
