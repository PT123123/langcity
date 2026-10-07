attribute float surfaceId;

                    ${globalUBO_default}
                    ${rotate_default}

                    uniform sampler2D tPosition;
                    uniform sampler2D tNormal;

                    uniform sampler2D tTexture1;
                    uniform sampler2D tTexture1Prev;

                    uniform vec3 uLightPos;
                    uniform float uMultiplier;
                    uniform float uShow;

                    varying vec2 vUv;
                    varying vec4 vPos;
                    varying vec3 vLDir;
                    varying vec3 vNormal;
                    varying vec2 vHighPrecisionZW;
                    flat varying float vSurfaceId;

                    mat2 rotate(float a) {
                        float s = sin(a);
                        float c = cos(a);
                        return mat2(c, s, -s, c);
                    }
                    vec3 hash31(float p) {
                        vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
                        p3 += dot(p3, p3.yzx+33.33);
                        return fract((p3.xxy+p3.yzz)*p3.zyx);
                        }

                    void main() {
                        vUv = uv;
                        vSurfaceId = fract(surfaceId + float(gl_InstanceID) * 5.435435);

                        int texWidth = textureSize(tTexture1, 0).x;
                        ivec2 texuv = ivec2(gl_InstanceID % texWidth, gl_InstanceID / texWidth);

                        vec4 currentOffset = texelFetch(tTexture1, texuv, 0);
                        vec4 prevOffset = texelFetch(tTexture1Prev, texuv, 0);

                        vec3 rand = hash31(float(gl_InstanceID));

                        vec3 pos = position * uShow;
                        float multiplier = uMultiplier;
                        float wingLength = abs(position.z);
                        float flapAnimation = sin(position.x * 5.0 + wingLength * 5.0 * multiplier - time * mix(10.0 * multiplier, 17.0, rand.x) * multiplier);
                        pos.y += flapAnimation * wingLength * 0.7;
                        pos *= mix(0.7, 1.2, rand.y);
                        pos.y -= 0.5;
                        pos.zy = rotate(0.6 * sin(time * multiplier + rand.z * 100.0 - pos.x)) * pos.zy;

                        vec3 forward = normalize(currentOffset.xyz - prevOffset.xyz);
                        vec3 up = normalize(currentOffset.xyz);
                        vec3 right = cross(forward, up);
                        mat3 TBN = mat3(forward, up, right);

                        pos = TBN * pos;
                        vec3 n = TBN * normal;

                        vNormal = normalize(normalMatrix * n);
                        vec3 wPos = pos + currentOffset.xyz;
                        vPos = viewMatrix * vec4(wPos, 1.0);

                        vLDir = (viewMatrix * vec4(normalize(uLightPos - wPos), 0.0)).xyz;

                        gl_Position = projectionMatrix * vPos;
                        vHighPrecisionZW = gl_Position.zw;
                    }
