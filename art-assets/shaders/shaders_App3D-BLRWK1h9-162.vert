attribute float hover;

                uniform float uSeed;
                uniform float uShow;

                ${globalUBO_default}
                ${rotate_default}
                ${falloff_default}
                ${slugvs_default}

                varying vec2 vUv;

                void main() {
                    vUv = uv;

                    mat4 imvpMatrix = projectionMatrix * modelViewMatrix * instanceMatrix;
                    vec3 pos = SlugVS(imvpMatrix) * vec3(vec2(hover), 1.0);
                    if (gl_InstanceID % 2 == 0) pos *= rotateZ(3.1416);

                    float insID = float(gl_InstanceID);
                    float scaleShow = falloff(insID, 0.0, ${e.instanceCount.toFixed(1)}, 5.0, uShow);
                    float steps = floor(2.0 + fract(uSeed * 45.35452 + insID * 2.546) * 3.0);
                    float scaleShowStepped = floor(scaleShow * steps) / steps;
                    pos *= scaleShowStepped;

                    gl_Position = imvpMatrix * vec4(pos, 1.0);;
                }
