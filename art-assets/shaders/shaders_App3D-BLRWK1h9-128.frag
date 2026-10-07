layout(location = 1) out highp vec4 gInfo;

            ${slugfs_default}

            varying vec2 vUv;
            varying vec2 vHighPrecisionZW;

            uniform sampler2D tCurve;
            uniform usampler2D tBand;
            uniform vec3 uColor1;
            uniform vec3 uColor2;

            void main() {
                vec4 color = RenderSlug(tCurve, tBand, vTexCoord, vColor, vBanding, vGlyph);
                if (color.w * vColor.w < 0.001) discard;

                gl_FragColor = vec4(color.rgb, 0.0);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec3(0.0));
            }
