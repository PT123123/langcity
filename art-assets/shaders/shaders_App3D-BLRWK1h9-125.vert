#if ! defined(GL_ANGLE_multi_draw)
                    #define gl_DrawID _gl_DrawID
                    uniform int _gl_DrawID;
                #endif
                uniform highp sampler2D batchingTexture;
                uniform highp usampler2D batchingIdTexture;

                vec4 getBatchingPositionScale(const in int i) {
                    int size = textureSize(batchingTexture, 0).x;
                    return texelFetch(batchingTexture, ivec2(i % size, i / size), 0);
                }

                float getIndirectIndex(const in int i) {
                    int size = textureSize(batchingIdTexture, 0).x;
                    int x = i % size;
                    int y = i / size;
                    return float(texelFetch(batchingIdTexture, ivec2(x, y), 0).r);
                }

                ${matrixutils_default}

                varying vec2 vUv;
                varying vec3 vPos;
                varying vec3 wPos;
                varying vec2 vHighPrecisionZW;
                varying float vDist;

                void main() {
                    vUv = uv;

                    vec4 posScale = getBatchingPositionScale(int(getIndirectIndex(gl_DrawID)));
                    wPos = (billboardModelMatrix(posScale.xyz) * vec4(position * posScale.w, 1.0)).xyz;
                    vPos = (viewMatrix * vec4(wPos, 1.0)).xyz;
                    vDist = distance(wPos, cameraPosition);

                    gl_Position = projectionMatrix * vec4(vPos, 1.0);
                    vHighPrecisionZW = gl_Position.zw;
                }
