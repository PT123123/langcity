${globalUBO_default}
            ${matrixutils_default}
            ${slugvs_default}

            varying vec2 vUv;
            varying vec3 vLocalPos;
            varying vec2 vHighPrecisionZW;

            uniform float uShowDistance;
            uniform float uScale;
            uniform float uShow;
            uniform float uPulse;
            uniform vec3 uWiggleDir;

            void main() {
                vUv = uv;

                vec3 pos = SlugVS();
                vLocalPos = pos;
                vec3 wPos = (modelMatrix * vec4(pos, 1.0)).xyz;

                float scale = smoothstep(uShowDistance, uShowDistance * 0.8, distance(wPos, cameraPosition)) * uScale * uShow;
                scale = mix(scale, scale * 1.2, uPulse);

                pos *= scale;
                pos += uWiggleDir * (0.05 + 0.05 * sin(time * 4.0));

                gl_Position = projectionMatrix * viewMatrix * billboardModelMatrix() * vec4(pos, 1.0);
                vHighPrecisionZW = gl_Position.zw;
            }
