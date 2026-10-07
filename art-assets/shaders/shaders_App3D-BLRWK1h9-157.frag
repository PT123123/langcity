layout(location = 1) out highp vec4 gInfo;

            // for shadows
            #include <packing>
            #include <shadowmap_pars_fragment>

            ${globalUBO_default}
            ${encoding_default}
            ${sinenoise_default}
            ${colorutils_default}
            ${fog_default}

            varying vec2 vUv;
            varying vec4 vPos;
            varying vec4 vRand;
            varying vec2 vHighPrecisionZW;
            flat varying vec3 vCentrTree;
            flat varying int vDetail;
            flat varying vec3 vNormal;
            flat varying vec3 vLightDir;
            flat varying float vColor;

            uniform sampler2D tTrees;
            uniform sampler2D tTreeDetail;
            uniform vec3 uColor1;
            uniform vec3 uColor2;
            uniform vec3 uColor3;
            uniform vec2 uNearFar;

            void main() {
                float surfaceId = fract((vCentrTree.x + vCentrTree.y + vCentrTree.z) * 3.424);
                float negativeDistance = perspectiveDepthToViewZ(gl_FragCoord.z, uNearFar.x, uNearFar.y);

                if (vDetail == 1) {
                    float shapes = 5.0;
                    float shapesStep = 1.0 / shapes;
                    float offset = floor(mod((vRand.z * 4.35 + vRand.w * 43.5) * shapes, shapes));
                    vec2 uv = vec2(vUv.x * shapesStep + offset * shapesStep, vUv.y);
                    float shape = texture2D(tTreeDetail, uv).r;
                    if (shape > 0.9) discard;

                    surfaceId = fract(vRand.x * 32.234);

                    // move details nearest to the camera
                    gl_FragDepth = viewZToPerspectiveDepth(negativeDistance + 0.2, uNearFar.x, uNearFar.y);
                } else {
                    float shape = texture2D(tTrees, vUv).r;
                    if (shape > 0.9) discard;

                    float noise = sinenoise1(vec3(vUv * mix(0.8, 1.0, vRand.z) * 5.0, time * 0.1));
                    gl_FragDepth = viewZToPerspectiveDepth(negativeDistance + noise * 0.1, uNearFar.x, uNearFar.y);
                }

                float outlineContribution = step(sinenoise1(vec3(vUv * 2.0, vRand.x + vRand.w * 34.32)), 0.35);

                // light
                vec3 geometryNormal = normalize(vNormal);
                float light = dot(geometryNormal, normalize(vLightDir));

                // shadow
                float shadow = 0.0;
                #if defined(USE_SHADOWMAP) && NUM_DIR_LIGHTS > 0 && NUM_DIR_LIGHT_SHADOWS > 0
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

                vec3 grassColor = mix(uColor1, uColor2, clamp(vColor, 0.0, 1.0));
                grassColor = mix(grassColor, uColor3, clamp(vColor - 1.0, 0.0, 1.0));

                vec3 colorhsv = rgb2hsv(grassColor);
                vec3 colorShadow = colorhsv;
                colorShadow.r -= 0.02;
                colorShadow.b *= 0.5;
                colorShadow = hsv2rgb(colorShadow);

                vec3 color = mix(colorShadow, grassColor, smoothstep(0.0, 0.1, light));

                addFog(color, vPos.z);

                gl_FragColor = vec4(color, surfaceId);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), vec2(0.0), outlineContribution);
            }
