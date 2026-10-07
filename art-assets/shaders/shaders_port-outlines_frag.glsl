${globalUBO_default}

                uniform sampler2D tDiffuse;
                uniform sampler2D tInfo;

                uniform float uCameraNear;
                uniform float uCameraFar;

                uniform vec2 uOutlineDepth;

                uniform vec2 uOutlineFade;
                uniform float uOutlineThickness;
                uniform vec3 uOutlineColor;
                uniform float uOutlineScale;

                uniform vec3 uInfoRange;
                uniform vec3 uDepthRange;
                uniform vec3 uNormalRange;
                uniform float uSmoothMargin;
                uniform float uInfoMinScale;

                ${lut_default}
                uniform sampler3D tLUT;
                uniform float uLUTIntensity;

                varying vec2 vUv;

                ${fit_default}
                ${depth_default}
                ${encoding_default}
                ${custom_default}

                void main() {
                    vec2 uv = vUv;
                    float aspect = resolution.x / resolution.y;

                    // get scene color
                    vec4 scene = texture2D(tDiffuse, vUv);
                    vec3 sceneColor = scene.rgb;

                    // compensate outline scale with resolution
                    float resScale = min(1.0, resolution.y / 1300.0) * uOutlineScale;

                    // get outline value
                    float centerDepth = 0.0;
                    float nearestDepth = 0.0;
                    float outlineValue = outline(tDiffuse, tInfo, vUv, uOutlineThickness, resScale, uInfoRange, uDepthRange, uNormalRange, uSmoothMargin, uInfoMinScale, uOutlineFade, vec2(uCameraNear, uCameraFar), nearestDepth, centerDepth);

                    // add the outline to the scene
                    sceneColor = mix(sceneColor, uOutlineColor, outlineValue);

                    // add color correction
                    sceneColor = apply3DLUTTetrahedral(sceneColor, tLUT, uLUTIntensity);

                    // outline debug
                    // gl_FragColor = vec4(vec3(outlineValue), 1.0); // debug

                    gl_FragColor = vec4(sceneColor, 1.0);
                }