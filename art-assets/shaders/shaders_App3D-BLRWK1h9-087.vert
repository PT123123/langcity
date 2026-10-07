#if defined(ANIMATION_TRANSLATE) || defined(ANIMATION_MASK)
                attribute vec2 textWeights;
                attribute vec3 lineWeights;
                uniform vec2 uAnimationDirection;
                uniform float uAnimationOrder;
                uniform float uAnimationMargin;
                uniform float uAnimationProgress;
                varying float vAlpha;
                ${falloff_default}
            #endif

            ${globalUBO_default}
            ${slugvs_default}

            void main() {
                vec3 pos = SlugVS();

                #if defined(ANIMATION_TRANSLATE) || defined(ANIMATION_MASK)
                float weight = 0.0;
                #endif

                #if defined(ANIMATION_TRANSLATE)
                    #if ANIMATION_TRANSLATE == 1
                        weight = textWeights.x;
                    #elif ANIMATION_TRANSLATE == 2
                        weight = textWeights.y;
                    #elif ANIMATION_TRANSLATE == 3
                        weight = lineWeights.x;
                    #elif ANIMATION_TRANSLATE == 4
                        weight = lineWeights.y;
                    #elif ANIMATION_TRANSLATE == 5
                        weight = lineWeights.z;
                    #endif
                #endif

                #if defined(ANIMATION_MASK)
                    #if ANIMATION_MASK == 1
                        weight = textWeights.x;
                    #elif ANIMATION_MASK == 2
                        weight = textWeights.y;
                    #elif ANIMATION_MASK == 3
                        weight = lineWeights.x;
                    #elif ANIMATION_MASK == 4
                        weight = lineWeights.y;
                    #elif ANIMATION_MASK == 5
                        weight = lineWeights.z;
                    #endif
                #endif

                #if defined(ANIMATION_TRANSLATE) || defined(ANIMATION_MASK)
                    float a = falloffsmooth(abs(uAnimationOrder - weight), 0.0, 1.0, uAnimationMargin, clamp(uAnimationProgress, 0.0, 1.0));
                #endif

                #ifdef ANIMATION_TRANSLATE
                    vAlpha = a;
                    pos += vec3(uAnimationDirection, 0.0) * (1.0 - vAlpha);
                #endif

                #ifdef ANIMATION_MASK
                    vAlpha = 1.0;
                    vTexCoord += uAnimationDirection * (1.0 - a);
                #endif

                gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
            }
