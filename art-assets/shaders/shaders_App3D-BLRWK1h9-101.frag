layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}
            ${fit_default}
            ${encoding_default}
            ${linearstep_default}
            ${colorutils_default}
            ${triplanar_default}

            varying vec3 wPos;
            varying vec3 wNormal;
            varying vec3 vNormal;
            varying vec4 vPos;
            varying float vSurfaceId;
            flat varying int vElementId;

            uniform sampler2D tColors;
            uniform sampler2D tNoiseTerrain;
            uniform sampler2D tNoise;

            varying vec2 vUv;
            varying vec2 vHighPrecisionZW;

            // for shadows
            #include <packing>
            #include <shadowmap_pars_fragment>

            void main() {
                float shadowContribution = 1.0;
                float outlineContribution = 1.0;
                float surfaceId = vSurfaceId;

                // triplanar texture used for adding detail
                vec4 triplanarNoise = triplanar(tNoise, wNormal, wPos.xyz * 0.07, 1.0);
                float height = length(wPos);
                float grassMask = 0.0;
                float wetMask = 0.0;

                if (vElementId == 1) { // mountain
                    grassMask = step(0.15, max(0.0, -triplanarNoise.r * 1.5 + dot(wNormal, normalize(wPos))) - triplanarNoise.g * 0.35 + 0.1 - triplanarNoise.b * 0.05);

                    // apply rock striations
                    float n1 = sin(height * 0.025 + (wNormal.x + wNormal.y + wNormal.z) * 0.05 + (wPos.x + wPos.y + wPos.z) * 1.5);
                    float striations = texture2D(tNoise, vec2(n1 * 0.01, height * 0.07 - n1 * 0.02)).g;
                    striations = step(0.47, striations + triplanarNoise.r * 0.2 + triplanarNoise.g * 0.05);

                    surfaceId += striations * (1.0 - grassMask) * step(0.25, triplanarNoise.r);
                }

                vec2 colorUV = vUv;
                if (grassMask > 0.5) colorUV = vec2(0.15, 0.95);

                vec3 color = texture2D(tColors, colorUV).rgb;

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

                surfaceId += grassMask * 0.1;

                gl_FragColor = vec4(color, surfaceId);
                // gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(normalize(vNormal)), outlineContribution);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), outlineContribution);
            }
