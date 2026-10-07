${globalUBO_default}


                attribute float scalefactor;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying float vScaleFactor;
                varying vec3 vLocalPos;
                varying vec4 vPos;

                uniform sampler2D tNoise;

                void main() {
                    vLocalPos = position;

                    // vec2 displacementUv = uv;
                    // displacementUv.y *= 0.08;
                    // displacementUv * vec2(1.0, 0.5 + displacementUv.y * 0.5);
                    // displacementUv.y += time * 0.085;

                    // float n1 = texture2D(tNoise, displacementUv).r;

                    // float grad = 1.0 - abs(n1 - 0.5) * 2.0;
                    // grad = step(0.95, grad);

                    // vec3 pos = position + normal * grad * 0.03 * (1.0 - scalefactor * 1.75);
                    vec3 pos = position;

                    vPos = modelViewMatrix * vec4(pos, 1.0);

                    gl_Position = projectionMatrix * vPos;
                    vHighPrecisionZW = gl_Position.zw;
                    vUv = uv;
                    vUv2 = uv;
                    vScaleFactor = scalefactor;
                }
