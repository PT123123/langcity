// thanks android
            uniform sampler2D tCurves1;
            uniform usampler2D tBands1;
            uniform sampler2D tCurves2;
            uniform usampler2D tBands2;
            uniform sampler2D tCurves3;
            uniform usampler2D tBands3;
            uniform sampler2D tCurves4;
            uniform usampler2D tBands4;
            uniform sampler2D tCurves5;
            uniform usampler2D tBands5;

            uniform sampler2D tNoise;

            ${slugfs_default}

            varying vec2 vUv;
            flat varying int vBatchID;

            void main() {
                vec4 color;

                // can be optimized to use a single texture, but anyway
                if (vBatchID == 0) {
                    color = RenderSlug(tCurves1, tBands1, vTexCoord, vColor, vBanding, vGlyph);
                } else if (vBatchID == 1) {
                    color = RenderSlug(tCurves2, tBands2, vTexCoord, vColor, vBanding, vGlyph);
                } else if (vBatchID == 2) {
                    color = RenderSlug(tCurves3, tBands3, vTexCoord, vColor, vBanding, vGlyph);
                } else if (vBatchID == 3) {
                    color = RenderSlug(tCurves4, tBands4, vTexCoord, vColor, vBanding, vGlyph);
                } else if (vBatchID == 4) {
                    color = RenderSlug(tCurves5, tBands5, vTexCoord, vColor, vBanding, vGlyph);
                }

                if (color.w * vColor.w < 0.001) discard;

                gl_FragColor = vec4(color.rgb, 1.0);
            }
