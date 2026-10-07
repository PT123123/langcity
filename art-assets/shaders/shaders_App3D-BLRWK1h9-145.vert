varying vec4 vMvPos;
                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;

                void main() {
                    vMvPos = modelViewMatrix * vec4(position, 1.0);
                    vUv = uv;

                    gl_Position = projectionMatrix * vMvPos;
                    vHighPrecisionZW = gl_Position.zw;
                }
