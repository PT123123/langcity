layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}
            ${encoding_default}

            varying vec3 vNormal;
            varying vec2 vUv;
            varying vec2 vHighPrecisionZW;

            uniform sampler2D tNoise;
            uniform vec3 uColor;
            uniform vec3 uColor2;

            void main() {
                vec4 noise = texture(tNoise, vUv * 1.0);

                float outlineContribution = step(0.2, noise.r);
                float surfaceId = 0.34242;

                float facing = abs(dot(normalize(vNormal), normalize(vec3(0.0, 0.0, 1.0))));
                vec3 color = mix(uColor, uColor2, 1.0 - smoothstep(0.2, 0.8, facing));

                gl_FragColor = vec4(color, 1.0);
                gInfo = vec4(1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5), encodeNormalSpheremap(normalize(vNormal)), outlineContribution);
            }
