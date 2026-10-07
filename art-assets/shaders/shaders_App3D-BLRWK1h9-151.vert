${globalUBO_default}

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec4 vPos;

                void main() {
                    vec3 pos = position;

                    // push closer to ground so you can't see under it
                    pos -= normal * 0.0175;

                    vPos =  modelViewMatrix * vec4(pos, 1.0);

                    gl_Position = projectionMatrix * vPos;
                    vHighPrecisionZW = gl_Position.zw;
                    vUv = uv;
                }
