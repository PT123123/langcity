${globalUBO_default}

                attribute vec2 uv2;
                attribute float extrafoam;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying float vExtraFoam;
                varying vec4 vPos;

                void main() {
                    vPos = modelViewMatrix * vec4(position, 1.0);
                    gl_Position = projectionMatrix * vPos;
                    vHighPrecisionZW = gl_Position.zw;
                    vUv = uv;
                    vUv2 = uv2;
                    vExtraFoam = extrafoam;
                }
