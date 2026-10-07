attribute float hover;
                attribute float scaleHover;
                attribute int side;
                attribute int vertid;

                ${globalUBO_default}
                ${matrixutils_default}
                ${falloff_default}

                uniform float uSeed;
                uniform float uShow;
                uniform float uShadowOffset;
                uniform vec3 uColor;
                uniform vec3 uColorShadow;

                varying vec2 vUv;
                flat varying vec3 vColor;

                void main() {
                    vUv = uv;
                    vColor = uColor;

                    vec3 localPos = position;

                    float insID = float(gl_InstanceID);
                    float instanceSeed = fract((uSeed + hover) * 54.32 + insID * 45.54352 + float(vertid) * 31.2344);
                    float offset = (instanceSeed * 2.0 - 1.0) * 0.0125;
                    vec3 dir = normalize(vec3(position.xy, 0.0));
                    localPos += dir * offset;

                    float scaleShow = falloff(insID, 0.0, ${e.instanceCount.toFixed(1)}, 5.0, uShow);
                    float steps = floor(2.0 + fract(uSeed * 4.35452 + insID * 23.546) * 3.0);
                    float scaleShowStepped = floor(scaleShow * steps) / steps;

                    localPos.xy *= scaleHover * scaleShowStepped;

                    if (side == 1) {
                        float offsetScale = scaleHover == 1.0 ? 1.0 : 0.4;
                        localPos.xy += uShadowOffset * vec2(1.0, -1.0) * offsetScale;
                        vColor = uColorShadow;
                    }

                    vec4 pos = instanceMatrix * vec4(localPos, 1.0);
                    gl_Position = projectionMatrix * modelViewMatrix * pos;
                }
