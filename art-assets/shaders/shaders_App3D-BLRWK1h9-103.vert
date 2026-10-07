${globalUBO_default}
            ${triplanar_default}

            attribute float surfaceId;
            attribute int elementId;

            uniform sampler2D tNoise;

            varying vec2 vUv;
            varying vec2 vHighPrecisionZW;

            varying vec3 wNormal;
            varying vec3 wPos;
            varying vec4 vPos;
            varying vec3 vNormal;
            varying float vSurfaceId;
            flat varying int vElementId;

            // for shadows
            #include <shadowmap_pars_vertex>
            vec3 inverseTransformDirection( in vec3 dir, in mat4 matrix ) {
                return normalize( ( vec4( dir, 0.0 ) * matrix ).xyz );
            }

            void main() {
                vUv = uv;
                vElementId = elementId;
                vSurfaceId = surfaceId;

                // get world position
                vec3 pos = position;

                vec4 triplanarNoise = triplanar(tNoise, normal, pos.xyz * 0.07, 1.0);
                vec3 displacement = sin(triplanarNoise.r * 180.0 + floor(time * 6.0) * 0.25) * normalize(pos) * 0.5;
                pos.xyz += displacement.xyz;

                vec4 worldPosition = modelMatrix * vec4(pos, 1.0);

                wNormal = normal;
                wPos = position.xyz;
                vNormal = normalize(normalMatrix * normal);

                // this requires worldPosition and transformedNormal
                vec3 transformedNormal = vNormal;
                #include <shadowmap_vertex>

                vPos = viewMatrix * worldPosition;

                gl_Position = projectionMatrix * vPos;
                vHighPrecisionZW = gl_Position.zw;
            }
