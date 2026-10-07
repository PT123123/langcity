/* BATCHING */
                    #if ! defined(GL_ANGLE_multi_draw)
                        #define gl_DrawID _gl_DrawID
                        uniform int _gl_DrawID;
                    #endif
                    uniform highp sampler2D batchingTexture;
                    uniform highp usampler2D batchingIdTexture;

                    mat4 getBatchingMatrix(const in int i) {
                        int size = textureSize(batchingTexture, 0).x;
                        int j = i * 4;
                        int x = j % size;
                        int y = j / size;
                        vec4 v1 = texelFetch(batchingTexture, ivec2(x, y), 0);
                        vec4 v2 = texelFetch(batchingTexture, ivec2(x + 1, y), 0);
                        vec4 v3 = texelFetch(batchingTexture, ivec2(x + 2, y), 0);
                        vec4 v4 = texelFetch(batchingTexture, ivec2(x + 3, y), 0);
                        return mat4(v1, v2, v3, v4);
                    }

                    float getIndirectIndex(const in int i) {
                        int size = textureSize(batchingIdTexture, 0).x;
                        int x = i % size;
                        int y = i / size;
                        return float(texelFetch(batchingIdTexture, ivec2(x, y), 0).r);
                    }

                    /* SKINNING */
                    attribute vec4 skinIndex;
                    attribute vec4 skinWeight;
                    uniform sampler2D boneTexture;
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

                    varying vec2 vUv;

                    void main() {
                        vUv = uv;

                        float batchID = getIndirectIndex(gl_DrawID);
                        mat4 batchingMatrix = getBatchingMatrix(batchID);
                        mat4 boneMatX = getBoneMatrix(skinIndex.x, batchID);
                        mat4 boneMatY = getBoneMatrix(skinIndex.y, batchID);
                        mat4 boneMatZ = getBoneMatrix(skinIndex.z, batchID);
                        mat4 boneMatW = getBoneMatrix(skinIndex.w, batchID);

                        mat4 skinMatrix = mat4(0.0);
                        skinMatrix += skinWeight.x * boneMatX;
                        skinMatrix += skinWeight.y * boneMatY;
                        skinMatrix += skinWeight.z * boneMatZ;
                        skinMatrix += skinWeight.w * boneMatW;

                        // normal
                        vec3 objectNormal = vec4(skinMatrix * vec4(normal, 0.0)).xyz;
                        mat3 bm = mat3(batchingMatrix);
                        vec3 transformedNormal = objectNormal;
                        transformedNormal /= vec3(dot(bm[0], bm[0]), dot(bm[1], bm[1]), dot(bm[2], bm[2]));
                        transformedNormal = bm * transformedNormal;
                        transformedNormal = normalMatrix * transformedNormal;
                        vNormal = normalize(transformedNormal);

                        // position
                        vec4 skinVertex = vec4(position, 1.0);
                        vec4 skinned = vec4(0.0);
                        skinned += boneMatX * skinVertex * skinWeight.x;
                        skinned += boneMatY * skinVertex * skinWeight.y;
                        skinned += boneMatZ * skinVertex * skinWeight.z;
                        skinned += boneMatW * skinVertex * skinWeight.w;
                        vec4 mvPosition = vec4(skinned.xyz, 1.0);
                        mvPosition = batchingMatrix * mvPosition;

                        mvPosition = modelViewMatrix * mvPosition;
                        gl_Position = projectionMatrix * mvPosition;
                    }
