attribute float randomm;
                attribute float thickness;
                attribute vec3 nextpos;
                attribute vec3 prevpos;
                attribute vec3 curvepos;
                attribute vec2 uv2;

                ${globalUBO_default}
                ${fit_default}

                uniform float uWidth;
                uniform sampler2D tNoise;

                varying vec2 vHighPrecisionZW;
                varying vec2 vUv;
                varying vec2 vUv2;
                varying vec3 vWorldPos;
                varying vec4 vPos;
                varying float vRandom;
                varying float vFresnel;
                varying float vThickness;

                void main() {
                    vUv = uv;
                    vUv2 = uv2;
                    vRandom = randomm;
                    vThickness = thickness;

                    vec4 worldPos = modelMatrix * vec4(curvepos, 1.0);
                    vec4 worldPrevPos = modelMatrix * vec4(prevpos, 1.0);
                    vec4 worldNextPos = modelMatrix * vec4(nextpos, 1.0);

                    // for animation offset in fragment shader
                    vWorldPos = curvepos.xyz;

                    vPos = viewMatrix * worldPos;

                    mat4 projView = projectionMatrix * viewMatrix;
                    vec4 finalPos = projView * worldPos;
                    vec4 finalPrevPos = projView * worldPrevPos;
                    vec4 finalNextPos = projView * worldNextPos;

                    float aspect = resolution.x / resolution.y;
                    vec2 aspectVec = vec2(aspect, 1.0);
                    vec2 posScreen = finalPos.xy / finalPos.w * aspectVec;
                    vec2 prevPosScreen = finalPrevPos.xy / finalPrevPos.w * aspectVec;
                    vec2 nextPosScreen = finalNextPos.xy / finalNextPos.w * aspectVec;

                    // calculate screen space line normal, so we can extrude it to give it thickness
                    vec2 dirA = normalize((posScreen - prevPosScreen));
                    vec2 dirB = normalize((nextPosScreen - posScreen));
                    vec2 tangent = normalize(dirA + dirB);
                    vec2 normal = normalize(vec2(-tangent.y, tangent.x));

                    // choose which direction to extrude
                    if (uv.x > 0.5) {
                        normal = -normal;
                    }
                    normal.x /= aspect;

                    // calculate fresnel so we can fade the smoke at harsh corners
                    // bias it to one side, as broken geometry only appears when
                    // lines are moving away from camera
                    // vFresnel = 1.0 - dot(normalize(finalPrevPos.xyz - finalPos.xyz), vec3(0.0, 0.0, -1.0));
                    // vFresnel = smoothstep(0.15, 1.0, vFresnel);

                    // extrude line in screen space
                    float width = 0.35;
                    width = width * thickness * mix(0.25, 3.0, vUv2.y);
                    // width = width * mix(0.1, 1.0, smoothstep(1.0, 0.2, vUv2.y));
                    normal *= width;
                    vec4 thicknessOffset = vec4(normal.xy, 0.0, 0.0);

                    gl_Position = finalPos + thicknessOffset;

                    vHighPrecisionZW = gl_Position.zw;
                }
