layout(location = 1) out highp vec4 gInfo;

                    uniform sampler2D tAtlas;


                    varying vec2 vUv;
                    varying vec3 vNormal;
                    varying vec4 vPos;
                    varying vec3 vLDir;
                    varying vec2 vHighPrecisionZW;
                    flat varying float vSurfaceId;

                    ${colorutils_default}
                    ${fit_default}
                    ${encoding_default}
                    ${fog_default}

                    void main() {
                        vec3 baseColor = texture(tAtlas, vUv).rgb;
                        vec3 colorShadow = rgb2hsv(baseColor);
                        colorShadow.b *= 0.5;
                        colorShadow = hsv2rgb(colorShadow);

                        vec3 nvNormal = normalize(vNormal);
                        float sh = max(0.0, dot(nvNormal, normalize(vLDir)));
                        sh = 1.0 - step(0.4, sh);

                        vec3 col = mix(baseColor, colorShadow, sh);

                        addFog(col, vPos.z);

                        gl_FragColor = vec4(col, vSurfaceId);
                        gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(nvNormal), 1.0);
                    }
