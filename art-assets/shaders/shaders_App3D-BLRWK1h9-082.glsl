#define outPos pc_fragColor
                    uniform sampler2D tTexture1;

                    layout(location = 1) out highp vec4 outVel;
                    uniform sampler2D tTexture2;

                    layout(location = 2) out highp vec4 outData;
                    uniform sampler2D tTexture3;

                    uniform sampler2D tSimInit;

                    ${globalUBO_default}
                    ${lerpfriction_default}
                    ${base_default}

                    void main() {
                        ivec2 uv = ivec2(gl_FragCoord.xy);

                        vec4 data1 = texelFetch(tTexture1, uv, 0);
                        vec4 data2 = texelFetch(tTexture2, uv, 0);
                        vec4 data3 = texelFetch(tTexture3, uv, 0);

                        vec3 position = data1.xyz;
                        float life = data1.w;
                        vec3 velocity = data2.xyz;
                        float random = data2.w;
                        vec3 up = data3.xyz;

                        // get particle id and index on emitting texture
                        int tsize = textureSize(tTexture1, 0).x;
                        int particleid = uv.y * tsize + uv.x;
                        int emitSize = textureSize(tSimInit, 0).x;
                        int indexEmitting = particleid * 3;
                        ivec2 emittinguv = ivec2(indexEmitting % emitSize, indexEmitting / emitSize);
                        vec4 simInit1 = texelFetch(tSimInit, emittinguv, 0);

                        if (simInit1.w > 0.0) {
                            // particle needs to spawn. get all info from spawn
                            vec4 simInit2 = texelFetch(tSimInit, emittinguv + ivec2(1, 0), 0);
                            vec4 simInit3 = texelFetch(tSimInit, emittinguv + ivec2(2, 0), 0);

                            position = simInit1.xyz;
                            life = simInit1.w;
                            velocity = simInit2.xyz;
                            random = simInit2.w;
                            data3 = simInit3;
                        } else if (life > 0.0) {
                            // substract life
                            life -= 0.01 * dtRatio;

                            // add upward force to velocity
                            velocity += up * 0.00075 * dtRatio;

                            // add curl noise
                            vec3 curl = BitangentNoise4D(vec4(vec3(position * 1.15 + random * 20.23), time * 0.2));
                            velocity += curl * 0.0005 * dtRatio;

                            // add friction
                            velocity *= frictionFPS(0.9, dtRatio);

                            // add to position
                            position += velocity * dtRatio;
                        }

                        outPos = vec4(position, life);
                        outVel = vec4(velocity, random);
                        outData = data3;
                    }
