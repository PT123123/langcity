${globalUBO_default}
    ${fit_default}

    #ifdef IS_TERRAIN
        attribute int surfaceId;
        attribute int elementId;
        flat varying int vElementId;
        varying vec3 vLocalNormal;
    #else
        attribute float surfaceId;
    #endif

    #if defined (IS_CHARACTER) || defined(IS_NPC)
        varying vec3 lPos;
    #endif

    #ifdef IS_CHARACTER
        flat varying int vIsLocal;
        flat varying float vBatchID;
    #endif

    varying vec3 vViewPosition;

    varying vec2 vUv;
    varying vec3 wPos;
    varying vec3 wNormal;
    varying vec3 vReflect;
    varying vec2 vHighPrecisionZW;
    flat varying float vSurfaceId;

    #include <common>
    #include <batching_pars_vertex>
    #include <normal_pars_vertex>

    // custom skinning_pars_vertex
    #ifdef USE_SKINNING
        uniform sampler2D boneTexture;

        #ifdef IS_CHARACTER
            mat4 bindMatrix = mat4(1.0);
            mat4 bindMatrixInverse = mat4(1.0);
            mat4 getBoneMatrix(const in float i, const in float id) {
                int x = int(i) * 4;
                int y = int(id);
                vec4 v1 = texelFetch(boneTexture, ivec2(x, y), 0);
                vec4 v2 = texelFetch(boneTexture, ivec2(x + 1, y), 0);
                vec4 v3 = texelFetch(boneTexture, ivec2(x + 2, y), 0);
                vec4 v4 = texelFetch(boneTexture, ivec2(x + 3, y), 0);
                return mat4(v1, v2, v3, v4);
            }
        #else
            uniform mat4 bindMatrix;
            uniform mat4 bindMatrixInverse;
            mat4 getBoneMatrix(const in float i) {
                int size = textureSize(boneTexture, 0).x;
                int j = int(i) * 4;
                int x = j % size;
                int y = j / size;
                vec4 v1 = texelFetch(boneTexture, ivec2(x, y), 0);
                vec4 v2 = texelFetch(boneTexture, ivec2(x + 1, y), 0);
                vec4 v3 = texelFetch(boneTexture, ivec2(x + 2, y), 0);
                vec4 v4 = texelFetch(boneTexture, ivec2(x + 3, y), 0);
                return mat4(v1, v2, v3, v4);
            }
        #endif
    #endif

    #include <shadowmap_pars_vertex>

    void main() {
        #ifdef IS_TERRAIN
            vElementId = elementId;
            vLocalNormal = normal;
            vSurfaceId = fract(float(surfaceId) / 10e5);
        #else
            vSurfaceId = surfaceId;
        #endif

        #include <uv_vertex>

        #if defined(USE_BATCHING) && !defined(IS_TERRAIN) // terrain is static, not moved by batched texture
            float batchID = getIndirectIndex(gl_DrawID);
            mat4 batchingMatrix = getBatchingMatrix(batchID);

            #ifdef IS_CHARACTER
                vBatchID = batchID;
                vSurfaceId += 0.02535 * batchID;
                vIsLocal = batchID == 0.0 ? 1 : 0;
            #endif
        #endif

        #if defined (IS_CHARACTER) || defined(IS_NPC)
            lPos = position;
        #endif

        #include <beginnormal_vertex>

        #ifdef USE_SKINNING
            #ifdef IS_CHARACTER
                mat4 boneMatX = getBoneMatrix(skinIndex.x, batchID);
                mat4 boneMatY = getBoneMatrix(skinIndex.y, batchID);
                mat4 boneMatZ = getBoneMatrix(skinIndex.z, batchID);
                mat4 boneMatW = getBoneMatrix(skinIndex.w, batchID);
            #else
                mat4 boneMatX = getBoneMatrix(skinIndex.x);
                mat4 boneMatY = getBoneMatrix(skinIndex.y);
                mat4 boneMatZ = getBoneMatrix(skinIndex.z);
                mat4 boneMatW = getBoneMatrix(skinIndex.w);
            #endif
        #endif

        #include <skinnormal_vertex>

        // custom defaultnormal_vertex
        vec3 transformedNormal = objectNormal;
        #if defined(USE_BATCHING) && !defined(IS_TERRAIN) // terrain is static, not moved by batched texture
            mat3 bm = mat3( batchingMatrix );
            transformedNormal /= vec3( dot( bm[ 0 ], bm[ 0 ] ), dot( bm[ 1 ], bm[ 1 ] ), dot( bm[ 2 ], bm[ 2 ] ) );
            transformedNormal = bm * transformedNormal;
        #endif
        #ifdef USE_INSTANCING
            mat3 im = mat3( instanceMatrix );
            transformedNormal /= vec3( dot( im[ 0 ], im[ 0 ] ), dot( im[ 1 ], im[ 1 ] ), dot( im[ 2 ], im[ 2 ] ) );
            transformedNormal = im * transformedNormal;
        #endif
        transformedNormal = normalMatrix * transformedNormal;
        #ifdef FLIP_SIDED
            transformedNormal = - transformedNormal;
        #endif

        #include <normal_vertex>
        #include <begin_vertex>
        #include <skinning_vertex>

        // custom project_vertex
        vec4 mvPosition = vec4(transformed, 1.0);

        #if defined(USE_BATCHING) && !defined(IS_TERRAIN)
            mvPosition = batchingMatrix * mvPosition;
        #endif
        #ifdef USE_INSTANCING
            mvPosition = instanceMatrix * mvPosition;
        #endif

        vec4 worldPosition = modelMatrix * mvPosition;

        // shake, anything custom...

        wPos = worldPosition.xyz;
        vec4 viewPosition = viewMatrix * worldPosition;
        gl_Position = projectionMatrix * viewPosition;

        vViewPosition = -viewPosition.xyz;

        #include <shadowmap_vertex>

        wNormal = inverseTransformDirection(transformedNormal, viewMatrix);
        vReflect = reflect(wNormal, normalize(worldPosition.xyz - cameraPosition.xyz));
        vHighPrecisionZW = gl_Position.zw;
    }
