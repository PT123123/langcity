varying vec2 vHighPrecisionZW;
                varying vec3 vNormal;
                varying vec3 vPos;
                varying vec3 vMvPos;

                void main() {
                    vPos = position;
                    vMvPos = vec3(modelViewMatrix * vec4(position, 1.0));
                    gl_Position = projectionMatrix * vec4(vMvPos, 1.0);
                    vHighPrecisionZW = gl_Position.zw;
                    vNormal = normalize(normalMatrix * normal);
                }
