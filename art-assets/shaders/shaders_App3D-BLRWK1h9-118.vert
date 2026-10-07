attribute float surfaceId;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying float vSurfaceId;

                void main() {
                    vSurfaceId = surfaceId;
                    vUv = uv;
                    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
                    vHighPrecisionZW = gl_Position.zw;
                }
