layout(location = 1) out highp vec4 gInfo;

                ${encoding_default}
                ${colorutils_default}
                ${sinenoise_default}
                ${fog_default}

                uniform sampler2D tEmojis;
                uniform sampler2D tAtlas;

                varying vec2 vUv;
                varying vec3 lPos;
                varying vec4 vPos;
                varying vec3 vNormal;
                flat varying vec3 vLightDir;
                flat varying float vScale;
                flat varying float vRand;
                flat varying float vSurfaceId;
                varying vec2 vHighPrecisionZW;

                // for shadows
                #include <packing>
                #include <shadowmap_pars_fragment>

                void main() {

                    vec3 geometryNormal = normalize(vNormal);
                    float light = dot(geometryNormal, normalize(vLightDir));

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

                    light = min(light, shadow);

                    // set color
                    vec3 color = texture2D(tAtlas, vUv).rgb;
                    vec3 colorShadow = rgb2hsv(color);
                    colorShadow.r -= 0.02;
                    colorShadow.b *= 0.5;
                    colorShadow = hsv2rgb(colorShadow);
                    float shadowCut = smoothstep(0.2, 0.4, light);
                    color = mix(colorShadow, color, shadowCut);

                    addFog(color, vPos.z);

                    gl_FragColor = vec4(color, vSurfaceId);

                    float outlineNoise = sinenoise1(lPos * 25.0 + vec3(3.324, 34.2, 56.343) * vRand) * 0.5 + 0.5;
                    float contribution = step(0.3, outlineNoise);
                    gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(geometryNormal), contribution);
                }
