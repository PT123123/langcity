${globalUBO_default}
                ${falloff_default}
                ${colorutils_default}

                uniform sampler2D tScene;
                uniform float uWipe1;
                uniform float uWipe2;
                uniform vec3 uWipeColor;
                uniform float uOverlay;
                uniform vec3 uOverlayColor;
                uniform float uFlash;

                varying vec2 vUv;

                void main() {
                    vec4 scene = texture2D(tScene, vUv);
                    vec3 color = scene.rgb;

                    // overlay
                    color = mix(color, uOverlayColor, clamp(uOverlay, 0.0, 1.0) * 0.9);

                    // wipes
                    if (uFlash > 0.0) {
                        color = vibrance(color, uFlash * 1.0);
                        color = brightnessContrast(color, uFlash, 1.0);
                    }

                    float inclination1 = 0.3 * uWipe1;
                    float uv1 = vUv.y - (1.0 - vUv.x) * inclination1;
                    float wipe1 = falloff(uv1, 1.0, -inclination1, 1e-6, uWipe1);

                    float inclination2 = 0.3 * (1.0 - uWipe2);
                    float uv2 = vUv.y - vUv.x * inclination2;
                    float wipe2 = falloff(uv2, -inclination2, 1.0, 1e-6, uWipe2);

                    color = mix(color, uWipeColor, wipe1);
                    color = mix(color, uWipeColor, wipe2);

                    gl_FragColor = vec4(color, 1.0);
                }
