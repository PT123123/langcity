layout(location = 1) out highp vec4 gInfo;

            ${globalUBO_default}

            uniform vec3 uColor;

            void main() {

                float outlineContribution = 1.0;
                float surfaceId = 1.0;
                vec3 color = uColor;
                gl_FragColor = vec4(color, surfaceId);
                gInfo = vec4(0.0, vec2(0.0), outlineContribution);

            }
