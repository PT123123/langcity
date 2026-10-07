layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}
            ${fit_default}
            ${encoding_default}
            ${linearstep_default}
            ${colorutils_default}
            ${sinenoise_default}
            ${fog_default}

            varying vec3 wPos;
            varying vec3 wNormal;
            varying vec3 vNormal;
            varying vec4 vPos;

            uniform sampler2D tColors;
            uniform sampler2D tNoiseTerrain;
            uniform sampler2D tGrass;

            ${getTerrainNoise()}

            varying vec2 vUv;
            varying vec4 vRand;
            varying vec2 vHighPrecisionZW;

            // for shadows
            #include <packing>
            #include <shadowmap_pars_fragment>

            void main() {
                float shadowContribution = 1.0;
                float outlineContribution = 1.0;

                vec3 color = vec3(0.0);

                #if NUM_DIR_LIGHTS > 0
                    float grassUVAmount = 10.0;
                    float grassUVX = mix(vUv.x, 1.0 - vUv.x, step(0.5, vRand.w));
                    vec2 grassUV = vec2(fract(grassUVX / grassUVAmount + 1.0 / grassUVAmount * floor(vRand.y * grassUVAmount)), vUv.y * 0.5 + 0.5 * floor(mod(vRand.z * 2.0 + vRand.x * 3.32, 2.0)));
                    float shape = texture2D(tGrass, grassUV).r;
                    if (shape > 0.1) discard;

                    // get color and add noise
                    vec3 wNorm = normalize(wNormal);
                    vec3 baseColor = applyTerrainColor(wNorm, wPos, texture2D(tColors, vec2(0.15, 0.95)).rgb);
                    vec3 colorhsv = rgb2hsv(baseColor);

                    vec3 baseColor2 = hsv2rgb(colorhsv - vec3(0.0, 0.0, 0.075));
                    vec3 baseColor3 = hsv2rgb(colorhsv + vec3(0.0, 0.0, 0.075));

                    // decide which color to use
                    vec3 grassColor = mix(baseColor, baseColor2, step(0.5, fract(vRand.x * 34.324 + vRand.y * 21.231)));
                    grassColor = mix(grassColor, baseColor3, step(0.5, fract(vRand.z * 5.53 + vRand.w * 4.423)));

                    // add noise to the outline, if the grass color is different than the baseColor, add a chance to remove the outline
                    outlineContribution *= step(0.4, sinenoise1(vec3((vUv + vec2(vRand.x * 3.34, vRand.y * 3.1)) * 7.0, vRand.z * 12.312312)) * 0.5 + 0.5);

                    // color shadow
                    vec3 colorShadow = rgb2hsv(grassColor);
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
                    color = mix(colorShadow, grassColor, shadowCut);
                #endif

                // remove outline from the bottom
                outlineContribution *= step(0.015, vUv.y) /* step(0.5, vRand.y)*/;

                float surfaceId = vRand.x;

                // fog
                // addFog(color, vPos.z);

                gl_FragColor = vec4(color, surfaceId);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(normalize(vNormal)), outlineContribution);
            }
