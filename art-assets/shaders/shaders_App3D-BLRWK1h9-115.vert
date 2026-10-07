${globalUBO_default}
            ${matrixutils_default}

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

            attribute float surfaceId;

            varying float vSurfaceId;
            varying vec2 vUv;
            varying vec3 vNormal;
            varying vec2 vHighPrecisionZW;

            vec3 hash31(float p) {
                vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
                p3 += dot(p3, p3.yzx+33.33);
                return fract((p3.xxy+p3.yzz)*p3.zyx);
            }

            mat4 rotation3D(vec3 axis, float angle) {
                axis = normalize(axis);
                float s = sin(angle);
                float c = cos(angle);
                float oc = 1.0 - c;

                return mat4(oc * axis.x * axis.x + c, oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
                            oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c, oc * axis.y * axis.z - axis.x * s,  0.0,
                            oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,  0.0,
                            0.0, 0.0, 0.0, 1.0);
            }

            void main() {
                vSurfaceId = surfaceId;
                vUv = uv;

                float batchID = getIndirectIndex(gl_DrawID);
                mat4 batchingMatrix = getBatchingMatrix(int(batchID));

                vec3 norm = normal;
                mat3 bm = mat3(batchingMatrix);
                norm /= vec3(dot(bm[0], bm[0]), dot(bm[1], bm[1]), dot(bm[2], bm[2]));
                norm = bm * norm;
                vNormal = normalize(normalMatrix * norm);

                // random stepped rotation animation
                float t = floor(time * 3.0);
                vec3 axis = normalize(hash31(batchID + t) * 2.0 - 1.0);
                float angle = 0.03;

                vec4 pos = vec4(position, 1.0);
                pos = rotation3D(axis, angle) * pos;

                gl_Position = projectionMatrix * modelViewMatrix * batchingMatrix * pos;
                vHighPrecisionZW = gl_Position.zw;
            }
