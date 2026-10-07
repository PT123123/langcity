#if !defined(USE_INSTANCING)
                            #define gl_InstanceID _gl_InstanceID
                            attribute int _gl_InstanceID;
                        #endif

                        ${matrixutils_default}

                        uniform sampler2D tTexture1;
                        uniform sampler2D tTexture2;
                        uniform sampler2D tTexture3;

                        uniform highp usampler2D instancingIdTexture;

                        vec4 getInfo(const in sampler2D map, const in int i) {
                            int size = textureSize(map, 0).x;
                            return texelFetch(map, ivec2(i % size, i / size), 0);
                        }

                        float getIndirectIndex(const in int i) {
                            int size = textureSize(instancingIdTexture, 0).x;
                            return float(texelFetch(instancingIdTexture, ivec2(i % size, i / size), 0).r);
                        }

                        varying vec2 vUv;
                        flat varying float vScale;
                        flat varying float vRand;
                        varying vec2 vHighPrecisionZW;

                        void main() {
                            vUv = uv;

                            int instanceID = int(getIndirectIndex(gl_InstanceID));
                            vec4 info1 = getInfo(tTexture1, instanceID);
                            vec3 offset = info1.rgb;
                            float life = info1.a;

                            vScale = smoothstep(0.0, 0.15, life) * smoothstep(1.0, 0.7, life);

                            vec4 wPos = billboardModelMatrix(offset) * vec4(position * vScale, 1.0);

                            gl_Position = projectionMatrix * viewMatrix * wPos;
                            vHighPrecisionZW = gl_Position.zw;

                            vec4 info2 = getInfo(tTexture2, instanceID);
                            vRand = info2.a;
                        }
