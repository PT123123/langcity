/* BATCHING */
                #if ! defined(GL_ANGLE_multi_draw)
                    #define gl_DrawID _gl_DrawID
                    uniform int _gl_DrawID;
                #endif

                attribute int emoji;
                attribute float surfaceId;

                ${matrixutils_default}
                ${rotate_default}
                ${globalUBO_default}

                uniform sampler2D tTexture1;
                uniform sampler2D tTexture2;
                uniform sampler2D tTexture3;

                uniform highp usampler2D batchingIdTexture;

                vec4 getInfo(const in sampler2D map, const in int i) {
                    int size = textureSize(map, 0).x;
                    return texelFetch(map, ivec2(i % size, i / size), 0);
                }

                float getIndirectIndex(const in int i) {
                    int size = textureSize(batchingIdTexture, 0).x;
                    return float(texelFetch(batchingIdTexture, ivec2(i % size, i / size), 0).r);
                }

                varying vec2 vUv;
                varying vec3 lPos;
                varying vec4 vPos;
                varying vec3 vNormal;
                flat varying vec3 vLightDir;
                flat varying float vScale;
                flat varying float vRand;
                flat varying float vSurfaceId;
                varying vec2 vHighPrecisionZW;

                // for light direction
                struct DirectionalLight {
                    vec3 direction;
                    vec3 color;
                };
                uniform DirectionalLight directionalLights[ 1 ];

                // for shadows
                #include <shadowmap_pars_vertex>
                vec3 inverseTransformDirection( in vec3 dir, in mat4 matrix ) {
                    return normalize( ( vec4( dir, 0.0 ) * matrix ).xyz );
                }

                void main() {
                    vUv = uv;
                    lPos = position;
                    vSurfaceId = surfaceId;

                    vLightDir = vec3(0.0);
                    #if NUM_DIR_LIGHTS > 0
                        vLightDir = normalize(directionalLights[0].direction);
                    #endif

                    int batchID = int(getIndirectIndex(gl_DrawID));
                    vec4 info1 = getInfo(tTexture1, batchID);
                    vec3 offset = info1.rgb;
                    float life = info1.a;

                    vec4 info2 = getInfo(tTexture2, batchID);
                    vRand = info2.a;

                    vec4 info3 = getInfo(tTexture3, batchID);
                    vec3 up = info3.rgb;

                    // tweak scale based on life
                    vScale = smoothstep(0.0, 0.15, life) * smoothstep(1.0, 0.7, life);

                    // rotate position according to the planet
                    mat4 planetRot = getMatrixRotation(viewMatrix);
                    vec3 pos = (vec4(position, 1.0) * planetRot).xyz;

                    // rotate around up vector
                    mat4 rot = rotation3D(up, time * 1.5 + (vRand + float(emoji)) * 32.2432);

                    // calculate world position and normal
                    vec3 wPos = offset + (rot * vec4(pos * vScale, 1.0)).xyz;
                    vNormal = normalize(normalMatrix * (rot * (vec4(normal, 0.0) * planetRot)).xyz);

                    vPos = viewMatrix * vec4(wPos, 1.0);

                    gl_Position = projectionMatrix * vPos;
                    vHighPrecisionZW = gl_Position.zw;

                    // this requires worldPosition and transformedNormal
                    vec3 transformedNormal = vNormal;
                    vec4 worldPosition = vec4(wPos, 1.0);
                    #include <shadowmap_vertex>
                }
