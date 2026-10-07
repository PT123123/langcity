#define outPos pc_fragColor
                    uniform sampler2D tTexture1;

                    layout(location = 1) out highp vec4 outVel;
                    uniform sampler2D tTexture2;

                    uniform float uNoise;
                    uniform float uGroups;
                    uniform float uSnap;
                    uniform float uSpeed;
                    uniform float uSeed;
                    uniform float uDirection;
                    uniform sampler2D tCurve;

                    varying vec2 vUv;

                    ${globalUBO_default}
                    ${lerpfriction_default}
                    ${sinenoise_default}
                    ${fit_default}

                    float hash11(float p) {
                        p = fract(p * .1031);
                        p *= p + 33.33;
                        p *= p + p;
                        return fract(p);
                    }

                    void main() {
                        ivec2 uv = ivec2(gl_FragCoord.xy);
                        vec4 prevPos = texelFetch(tTexture1, uv, 0);
                        vec4 prevVel = texelFetch(tTexture2, uv, 0);

                        float hashFlock = hash11(prevPos.w * 8.54534);
                        float hashVel = hash11(vUv.x);

                        // randomize the flock
                        float offset = floor(hashFlock / (1.0 / uGroups));
                        float direction = uDirection; // mix(-1.0, 1.0, step(0.5, hashFlock));
                        float speed = 2.0 * direction * uSpeed * mix(0.75, 1.0, step(0.3, hashVel));
                        float curveWidth = float(textureSize(tCurve, 0).x);
                        float progress = time * speed + (curveWidth / uGroups) * offset + uSeed * 12.4234;

                        vec3 c1 = texelFetch(tCurve, ivec2(mod(progress, curveWidth), 0), 0).rgb;
                        vec3 c2 = texelFetch(tCurve, ivec2(mod(progress + 1.0, curveWidth), 0), 0).rgb;
                        vec3 target = mix(c1, c2, fract(abs(progress)));

                        if (uSnap > 0.9) {
                            prevPos.xyz = target;
                            prevVel.xyz = vec3(0.0);
                        } else {
                            // add some noise
                            float nAmount = 0.005 * uNoise * dtRatio;
                            prevVel.x += sinenoise1(prevPos.xyz + prevVel.w * 53.5645 + time * 0.05) * nAmount;
                            prevVel.y += sinenoise1(prevPos.xyz + prevVel.w * 653.8667 + time * 0.1) * nAmount;
                            prevVel.z += sinenoise1(prevPos.xyz + prevVel.w * 21.65465 + time * 0.025) * nAmount;

                            // towards target
                            vec3 delta = (target - prevPos.xyz) * 0.0003;
                            prevVel.xyz += delta * dtRatio;

                            // friction
                            prevVel.xyz *= frictionFPS(0.99, dtRatio);

                            // add to position
                            prevPos.xyz += prevVel.xyz * dtRatio;
                        }

                        outVel = prevVel;
                        outPos = prevPos;
                    }
