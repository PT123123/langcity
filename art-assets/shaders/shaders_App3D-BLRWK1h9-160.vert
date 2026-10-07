uniform float uHover;
                uniform float uPosY;
                uniform float uShow;
                uniform float uScale;

                ${globalUBO_default}
                ${falloff_default}
                ${slugvs_default}

                varying vec2 vUv;

                void main() {
                    vUv = uv;

                    float last = ${e.instanceCount.toFixed(1)};
                    float scaleShow = falloff(last, 0.0, last, 5.0, uShow);
                    float scaleShowStepped = floor(scaleShow * 3.0) / 3.0;

                    vec3 pos = SlugVS() * 0.95 * uScale * vec3(vec2(uHover), 1.0) * scaleShowStepped + vec3(0.0, uPosY, 0.0);

                    // apply scale and
                    gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);;
                }
