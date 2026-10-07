${globalUBO_default}
            ${fit_default}
            ${sinenoise_default}

            attribute vec3 up;
            attribute vec4 randomm;
            uniform vec3 charPos;
            uniform float charSpeed;

            varying vec2 vUv;
            varying vec4 vRand;
            varying vec2 vHighPrecisionZW;

            varying vec3 wNormal;
            varying vec3 wPos;
            varying vec4 vPos;
            varying vec3 vNormal;

            // for shadows
            #include <shadowmap_pars_vertex>
            vec3 inverseTransformDirection( in vec3 dir, in mat4 matrix ) {
                return normalize( ( vec4( dir, 0.0 ) * matrix ).xyz );
            }

            void main() {
                vRand = randomm;
                vUv = uv;

                // get world position
                vec4 instancePos = instanceMatrix * vec4(position, 1.0);
                vec4 worldPosition = modelMatrix * instancePos;

                vec3 grassBottomPos = vec3(instanceMatrix[3]);
                vec3 grassDir = grassBottomPos - charPos;
                float grassDist = length(grassDir);

                // move up when looking in the up direction to prevent bottom outlines
                vec3 grassUp = normalize(up);
                vec3 grassCamDir = normalize(cameraPosition - grassBottomPos);
                float grassUpDisplacement = fit(max(0.0, dot(grassUp, grassCamDir)), 0.05, 0.3, 0.0, 1.0);

                vec3 grassOffset = grassBottomPos + grassUp * grassUpDisplacement * 0.02;
                vec3 camToGrass = normalize(grassOffset - cameraPosition);
                vec3 grassRight = cross(grassUp, camToGrass);
                vec3 grassForward = cross(grassRight, grassUp);
                mat3 grassTBN = mat3(grassRight, grassForward, grassUp);
                float grassScale = fit(fract(randomm.x + randomm.w * 2.0), 0.0, 1.0, 0.8, 1.3);

                vec3 grassPosition = position.xyz * grassScale;
                worldPosition = vec4(grassTBN * grassPosition + grassOffset, 1.0);

                // add noise
                float upMult = step(0.5, uv.y);
                float grassdisp = 0.1 + 0.2 * randomm.x;
                float grassspeed = 0.25 + 0.3 * randomm.y;
                worldPosition.xyz += grassRight * sinenoise1(vec3(grassBottomPos.x, 0.0, grassBottomPos.z) * vec3(0.05) + time * grassspeed) * grassdisp * upMult;
                worldPosition.xyz += grassRight * sinenoise1(vec3(grassBottomPos.x, 0.0, grassBottomPos.z) * vec3(0.1) + vec3(313.123) + time * grassspeed) * grassdisp * upMult;

                // repel by player movement
                vec3 grassDisp = normalize(grassDir) * fit(grassDist, 0.0, fit(charSpeed, 0.0, 0.01, 0.0, 1.25), 1.0, 0.0) * upMult * fit(charSpeed, 0.0, 0.15, 0.0, 0.3);
                if (length(grassDisp) > 0.001) {
                    grassDisp *= 1.0 - abs(dot(normalize(grassDisp), grassUp)); // displace mostly horizontally
                    worldPosition.xyz += grassDisp;
                }

                wNormal = grassUp;
                wPos = worldPosition.xyz;
                vNormal = normalize((viewMatrix * vec4(grassUp, 0.0)).xyz);

                // this requires worldPosition and transformedNormal
                vec3 transformedNormal = normalize(normalMatrix * normal);
                #include <shadowmap_vertex>

                vPos = viewMatrix * worldPosition;

                gl_Position = projectionMatrix * vPos;
                vHighPrecisionZW = gl_Position.zw;
            }
