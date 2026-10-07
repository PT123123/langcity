${globalUBO_default}

                uniform float uScale;
                varying vec2 vUv;

                void main() {
                    vUv = uv;

                    vec3 pos = position;
                    pos.x /= aspect;
                    pos /= resolutionUI.y / (300.0 * uScale);

                    gl_Position = modelMatrix * vec4(pos, 1.0);
                }
