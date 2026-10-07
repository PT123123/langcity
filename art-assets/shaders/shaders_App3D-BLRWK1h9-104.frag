layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}
            ${fit_default}
            ${encoding_default}
            ${linearstep_default}
            ${colorutils_default}
            ${triplanar_default}

            varying vec2 vUv;
            varying vec3 wPos;
            varying vec3 wNormal;
            varying vec3 vNormal;
            varying vec4 vPos;
            varying float vSurfaceId;
            flat varying int vElementId;

            varying vec2 vHighPrecisionZW;

            uniform vec3 uColor;
            uniform sampler2D tNoise;

            // for shadows
            #include <packing>
            #include <shadowmap_pars_fragment>

            void main() {

                float outlineContribution = 1.0;
                vec3 color = uColor;
                vec4 triplanarNoise = triplanar(tNoise, wNormal, wPos.xyz * 0.07, 1.0);

                #if NUM_DIR_LIGHTS > 0

                    // color shadow
                    vec3 colorShadow = rgb2hsv(color);
                    colorShadow.r -= 0.02;
                    colorShadow.b *= 0.5;
                    colorShadow = hsv2rgb(colorShadow);

                    // shadow
                    float shadow = 0.0;
                    #if defined(USE_SHADOWMAP) && NUM_DIR_LIGHT_SHADOWS > 0
                        DirectionalLightShadow directionalLightShadow;
                        directionalLightShadow = directionalLightShadows[0];
                        shadow = getShadow(
                            directionalShadowMap[0],
                            directionalLightShadow.shadowMapSize,
                            directionalLightShadow.shadowIntensity,
                            directionalLightShadow.shadowBias,
                            directionalLightShadow.shadowRadius,
                            vDirectionalShadowCoord[0]
                        );
                    #endif

                    // set color
                    float shadowCut = smoothstep(0.2, 0.4, shadow);
                    color = mix(colorShadow, color, shadowCut);
                #endif

                // break up outlines
                outlineContribution *= step(0.17, triplanarNoise.g * triplanarNoise.b);
                outlineContribution = step(0.5, outlineContribution);

                gl_FragColor = vec4(color, vSurfaceId);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(normalize(vNormal)), outlineContribution);
            }
