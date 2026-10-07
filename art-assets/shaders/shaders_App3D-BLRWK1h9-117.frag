layout(location = 1) out highp vec4 gInfo;

                ${globalUBO_default}
                ${falloff_default}

                varying vec3 vNoise;
                varying float vProgress;
                varying float vRotation;
                varying float vSize;
                varying vec2 vHighPrecisionZW;

                uniform sampler2D tSprites;
                uniform vec3 uColor;
                uniform float uShow1;

                mat2 rotate(float a) {
                    float s = sin(a);
                    float c = cos(a);
                    mat2 m = mat2(c, s, -s, c);
                    return m;
                }

                void main() {
                    vec2 uv = gl_PointCoord.xy;

                    // randomize sprite rotation
                    uv -= 0.5;
                    uv = rotate(vRotation) * uv;
                    uv += 0.5;

                    // scale uvs to match a single character of the spritesheet
                    uv.y = 1.0 - uv.y;
                    uv.x /= 16.0;
                    uv.x += 1.0 / 16.0;

                    // choose random sprite from spritesheet
                    uv.x += vProgress;

                    float sprite = texture2D(tSprites, uv).r;
                    float alpha = sprite;
                    if (alpha < 0.5) discard;

                    alpha *= smoothstep(0.0, 0.1, uShow1);

                    vec3 color = mix(uColor + uColor * 0.5, uColor * uColor, vNoise.r);

                    float outlineContribution = 0.0;
                    float depth = 1.0 - (0.5 * vHighPrecisionZW[0] / vHighPrecisionZW[1] + 0.5);

                    if (vSize > 1.5) {
                        outlineContribution = 0.1;
                        depth = 0.1; // overwrite to ignore outline fading on distance
                    }

                    gl_FragColor = vec4(color, alpha);
                    gInfo = vec4(depth, 0.0, 0.0, outlineContribution);
                }
