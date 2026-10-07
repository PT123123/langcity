uniform sampler2D tCurve;
            uniform usampler2D tBand;

            ${slugfs_default}

            #if defined(ANIMATION_TRANSLATE) || defined(ANIMATION_MASK)
                varying float vAlpha;
            #endif

            void main() {
                vec4 color = SlugFS(tCurve, tBand);

                #if defined(ANIMATION_TRANSLATE) || defined(ANIMATION_MASK)
                    color.a *= vAlpha;
                #endif

                gl_FragColor = color;
            }
