${blendmodes_default}

                uniform sampler2D tCircles;
                uniform vec2 uInnerPos;
                uniform float uAlpha;

                varying vec2 vUv;

                void main() {
                    vec2 bg = texture2D(tCircles, vUv).rg;
                    vec4 color = vec4(vec3(mix(vec3(0.0), vec3(1.0), bg.x)), bg.y);

                    float inner = texture2D(tCircles, vUv + uInnerPos).b;
                    color.rgb = blendScreen(color.rgb, vec3(mix(vec3(0.0), vec3(1.0), inner)));
                    color.a = max(color.a, inner * 0.6);

                    gl_FragColor = color;
                    gl_FragColor.a *= uAlpha;
                }
