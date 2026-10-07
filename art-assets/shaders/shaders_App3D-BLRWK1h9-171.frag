varying vec2 vUv;

                ${slugfs_default}

                uniform sampler2D tCurve;
                uniform usampler2D tBand;
                uniform vec3 uColor;

                void main() {
                    vec4 color = RenderSlug(tCurve, tBand, vTexCoord, vColor, vBanding, vGlyph);

                    if (color.w * vColor.w < 0.001) discard;

                    gl_FragColor = vec4(uColor, 1.0);
                }
