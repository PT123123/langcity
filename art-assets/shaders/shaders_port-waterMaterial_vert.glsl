${globalUBO_default}

            attribute float dist;
            attribute float surfaceId;
            attribute int elementId;

            varying vec2 vUv;
            varying vec2 vHighPrecisionZW;

            varying vec3 wNormal;
            varying vec3 wPos;
            varying vec4 vPos;
            varying vec3 vNormal;
            varying float vSurfaceId;
            varying float vDist;
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
                vDist = dist;

                // get world position
                vec4 worldPosition = modelMatrix * vec4(position, 1.0);

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