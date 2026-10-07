uniform float uShow;
                uniform float uHide;
                uniform vec3 uColor1;
                uniform vec3 uColor2;

                flat varying int vSide;
                varying vec2 vUv;

                ${fit_default}

                void main() {
                    vec3 color = vSide == 0 ? uColor1 : uColor2;

                    float showAmount = step(vUv.x, uShow);
                    float hideAmount = step(uHide, vUv.x);

                    // float hoverOut = step(fit(uHover, 0.0, 0.5, 0.0, 1.0), vUv.x);
                    // float hoverIn = 1.0 - step(fit(uHover, 0.5, 1.0, 0.0, 1.0), vUv.x);

                    float show = showAmount * hideAmount /* * max(hoverIn, hoverOut) */;
                    if (show < 0.0001) discard;

                    gl_FragColor = vec4(-color, 1.0);
                }
