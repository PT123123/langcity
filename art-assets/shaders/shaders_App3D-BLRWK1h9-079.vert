/* BATCHING */
                    #if ! defined(GL_ANGLE_multi_draw)
                        #define gl_DrawID _gl_DrawID
                        uniform int _gl_DrawID;
                    #endif

                    ${matrixutils_default}

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
                    flat varying float vScale;
                    flat varying float vRand;
                    varying vec2 vHighPrecisionZW;

                    void main() {
                        vUv = uv;

                        int batchID = int(getIndirectIndex(gl_DrawID));
                        vec4 info1 = getInfo(tTexture1, batchID);
                        vec3 offset = info1.rgb;
                        float life = info1.a;

                        vScale = smoothstep(0.0, 0.15, life) * smoothstep(1.0, 0.7, life);

                        vec4 wPos = billboardModelMatrix(offset) * vec4(position * vScale, 1.0);

                        gl_Position = projectionMatrix * viewMatrix * wPos;
                        vHighPrecisionZW = gl_Position.zw;

                        vec4 info2 = getInfo(tTexture2, batchID);
                        vRand = info2.a;
                    }
