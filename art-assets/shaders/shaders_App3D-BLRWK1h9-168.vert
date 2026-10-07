attribute int side;
                attribute int vertid;

                ${globalUBO_default}
                ${matrixutils_default}
                ${falloff_default}

                uniform float uSeed;
                uniform float uShow;
                uniform float uShadowOffset;
                uniform vec3 uColor;
                uniform vec3 uColorShadow;
                uniform float uScaleHover;

                varying vec2 vUv;
                flat varying vec3 vColor;

                void main() {
                    vUv = uv;
                    vColor = uColor;

                    vec3 localPos = position;

                    float steps = 4.0;
                    float scaleShowStepped = floor(uShow * steps) / steps;

                    float vertSeed = fract(uSeed * 533.32 + float(vertid) * 210.67644 + scaleShowStepped * 34.5435);
                    float offset = (vertSeed * 2.0 - 1.0) * 0.065;
                    vec3 dir = normalize(vec3(position.xy, 0.0));
                    localPos += dir * offset;

                    localPos.xy *= uScaleHover * scaleShowStepped;
                    localPos = (modelMatrix * vec4(localPos, 1.0)).xyz;

                    if (scaleShowStepped > 0.0) {
                        if (side == 1) { // backdrop shadow
                            float offsetScale = uScaleHover == 1.0 ? 1.0 : 0.4;
                            localPos.xy += uShadowOffset * vec2(1.0, -1.0) * offsetScale;
                            vColor = uColorShadow;
                        }
                    }

                    gl_Position = projectionMatrix * viewMatrix * vec4(localPos, 1.0);
                }
