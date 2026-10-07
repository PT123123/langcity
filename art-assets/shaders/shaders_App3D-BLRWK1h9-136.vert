/* BATCHING */
                #if ! defined(GL_ANGLE_multi_draw)
                    #define gl_DrawID _gl_DrawID
                    uniform int _gl_DrawID;
                #endif

                ${matrixutils_default}
                ${rotate_default}
                ${globalUBO_default}

                attribute int emoji;

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

                varying vec2 vHighPrecisionZW;

                void main() {
                    int batchID = int(getIndirectIndex(gl_DrawID));
                    vec4 info1 = getInfo(tTexture1, batchID);
                    vec3 offset = info1.rgb;
                    float life = info1.a;

                    vec4 info2 = getInfo(tTexture2, batchID);
                    float randd = info2.a;

                    vec4 info3 = getInfo(tTexture3, batchID);
                    vec3 up = info3.rgb;

                    // tweak scale based on life
                    float scale = smoothstep(0.0, 0.15, life) * smoothstep(1.0, 0.7, life);

                    // rotate position according to the planet
                    mat4 planetRot = getMatrixRotation(viewMatrix);
                    vec3 pos = (vec4(position, 1.0) * planetRot).xyz;

                    // rotate around up vector
                    mat4 rot = rotation3D(up, time * 1.5 + (randd + float(emoji)) * 32.2432);

                    // calculate world position and normal
                    vec3 wPos = offset + (rot * vec4(pos * scale, 1.0)).xyz;

                    gl_Position = projectionMatrix * viewMatrix * vec4(wPos, 1.0);
                    vHighPrecisionZW = gl_Position.zw;
                }
