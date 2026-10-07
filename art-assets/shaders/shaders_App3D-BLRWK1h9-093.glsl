uniform vec3 uFogColorNear;
uniform vec3 uFogColorFar;
uniform float uFogDistance;
uniform float uFogDensity;

void addFog(inout vec3 outcolor, float lenCam) {
    float fogFactor = 1.0 - exp(-uFogDensity * uFogDensity * lenCam * lenCam);
    float range1 = smoothstep(0.0, uFogDistance, fogFactor);
    float range2 = 1.0 - range1;
    vec3 fogColor = uFogColorNear * range2 + uFogColorFar * range1;
    outcolor = mix(outcolor, fogColor, fogFactor);
}
