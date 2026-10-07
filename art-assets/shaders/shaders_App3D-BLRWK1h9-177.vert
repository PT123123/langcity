attribute int side;
                    attribute int vertid;

                    ${globalUBO_default}
                    ${matrixutils_default}
                    ${rotate_default}
                    ${falloff_default}

                    uniform float uSeed;
                    uniform float uShow;
                    uniform float uShadowOffset;
                    uniform vec3 uColor;
                    uniform vec3 uColorShadow;

                    varying vec2 vUv;
                    flat varying vec3 vColor;

                    void main() {
                        vec3 localPos = position;

                        float steps = 4.0;
                        float scaleShowStepped = floor(uShow * steps) / steps;

                        float vertSeed = fract(uSeed * 54.32 + float(vertid) * 12.645 + scaleShowStepped * 34.5435);
                        float offset = (vertSeed * 2.0 - 1.0) * 0.02;

                        localPos.xy += vec2(0.5, -0.5);
                        vec3 dir = normalize(vec3(localPos.xy, 0.0));
                        localPos += dir * offset;
                        localPos.xy -= vec2(0.5, -0.5);

                        vec4 pos = vec4(localPos * scaleShowStepped, 1.0);
                        vec4 wPos = modelMatrix * pos;

                        vUv = uv;
                        vColor = uColor;

                        if (scaleShowStepped > 0.0) {
                            if (side == 1) { // backdrop shadow
                                wPos.xy += uShadowOffset * vec2(1.0, -1.0);
                                vColor = uColorShadow;
                            }
                        }

                        gl_Position = projectionMatrix * viewMatrix * wPos;
                    }
