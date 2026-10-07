layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}
            ${encoding_default}

            varying float vSurfaceId;
            varying vec2 vHighPrecisionZW;
            varying vec3 vNormal;
            varying vec2 vUv;

            uniform sampler2D tNoise;
            uniform vec3 uColor;
            uniform vec3 uColor2;

            void main() {
                float noise = texture(tNoise, vUv * 6.0).r;

                float outlineContribution = step(0.25, noise);
                float surfaceId = vSurfaceId;

                vec3 norm = normalize(vNormal);
                float facing = abs(dot(norm, normalize(vec3(0.0, 0.0, 1.0))));
                vec3 color = mix(uColor, uColor2, 1.0 - smoothstep(0.2, 0.8, facing));


                gl_FragColor = vec4(color, surfaceId);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(norm), outlineContribution);
            }
