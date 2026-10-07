varying vec2 vUv;

                uniform vec3 uColor;

                void main() {
                    if (length(vUv - 0.5) > 0.5) discard;

                    gl_FragColor = vec4(uColor, 1.0);
                }
