layout(location = 1) out highp vec4 gInfo;

            uniform sampler2D tCurve;
            uniform usampler2D tBand;

            flat varying vec3 vCentr;
            varying vec2 vHighPrecisionZW;

            ${globalUBO_default}
            ${slugfs_default}
            ${transformUV_default}

            void main() {
                // animation

                vec2 uv = vTexCoord;
                vec4 color = RenderSlug(tCurve, tBand, uv, vColor, vBanding, vGlyph);

                if (color.w * vColor.w < 0.01) discard;

                // skip outline
                gl_FragColor = vec4(color.xyz, 0.34242);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), 0.0);
            }
