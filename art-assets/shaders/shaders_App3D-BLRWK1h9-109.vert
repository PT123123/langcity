${globalUBO_default}

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec4 vPos;

                void main() {
                    vPos = modelViewMatrix * vec4(position, 1.0);

                    gl_Position = projectionMatrix * vPos;
                    vHighPrecisionZW = gl_Position.zw;
                    vUv = uv;
                }
