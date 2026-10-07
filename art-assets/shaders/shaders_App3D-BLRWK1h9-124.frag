uniform float uAlpha;
                varying vec2 vUv;

                void main() {
                    float dist = length(vUv - 0.5);
                    float margin = fwidth(vUv.x);
                    float d = smoothstep(0.4 + margin, 0.4, dist);

                    gl_FragColor.rgb = vec3(1.0);
                    gl_FragColor.a = 0.15 * d * uAlpha;
                }
