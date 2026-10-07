uniform float uShow;
                uniform float uSeed;
                uniform vec3 uColor;
                uniform bool uOverwriteColor;

                varying vec2 vUv;

                ${globalUBO_default}
                ${slugvs_default}
                ${falloff_default}
                ${rotate_default}

                float hash11(float p) {
                    p = fract(p * .1031);
                    p *= p + 33.33;
                    p *= p + p;
                    return fract(p);
                }

                void main() {
                    vUv = uv;
                    vec3 pos = SlugVS();

                    float rot = floor((time * 0.5 + uSeed * 34.23) * 7.0) / 7.0;
                    float angle = 0.03;
                    pos *= rotateZ(mix(-angle, angle, hash11(rot)));

                    float scaleShow = uShow;
                    float steps = floor(2.0 + fract(uSeed * 54.35452) * 3.0);
                    float scaleShowStepped = floor(scaleShow * steps) / steps;
                    pos *= scaleShowStepped;

                    if (uOverwriteColor) vColor.rgb = uColor;

                    gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
                }
