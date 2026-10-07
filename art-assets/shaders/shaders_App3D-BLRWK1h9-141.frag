layout(location = 1) out highp vec4 gInfo;

            uniform sampler2D tCurve;
            uniform usampler2D tBand;

            ${slugfs_default}
            ${globalUBO_default}

            varying vec2 vHighPrecisionZW;
            flat varying vec3 vCentr;

            void main() {
                vec2 uv = vTexCoord;
                vec4 color = RenderSlug(tCurve, tBand, uv, vColor, vBanding, vGlyph);

                gl_FragColor = vec4(color.xyz, color.w * vColor.w);

                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec3(0.0));
            }
