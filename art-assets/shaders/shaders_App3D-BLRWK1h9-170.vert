uniform float uHover;
                uniform float uShow;

                ${globalUBO_default}
                ${falloff_default}
                ${slugvs_default}

                varying vec2 vUv;

                void main() {
                    vUv = uv;

                    float showStepped = floor(uShow * 2.0) / 2.0;
                    vec3 pos = SlugVS() * vec3(vec2(uHover), 1.0) * showStepped;
                    gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
                }
