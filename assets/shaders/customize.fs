#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform sampler2D palettes;
uniform vec4      skyColor;

out vec4 finalColor;

vec4 getColor() {
    vec4 texel = texture(texture0, fragTexCoord);

    if (fragColor.a != 0) {
        return texel*fragColor;
    }

    int skaterId = int(fragColor.r * 255.0 + 0.5);

    vec4 first = texelFetch(palettes, ivec2(skaterId*6, 0), 0);
    if (first.a == 0.0) {
        return texel;
    }

    for (int i = 0; i < 5; i++) {
        vec3 orig = texelFetch(palettes, ivec2(i, 0), 0).rgb;
        if (texel.rgb == orig) {
            vec3 color = texelFetch(palettes, ivec2((skaterId * 6) + i, 0), 0).rgb;
            return vec4(color, 1.0);
        }
    }

    return texel;
}

void main() {
    finalColor = getColor();
    finalColor.rgb *= mix(vec3(1.0), skyColor.rgb, skyColor.a);
    // vec3 tinted = mix(finalColor.rgb, finalColor.rgb * skyColor.rgb, skyColor.a);
    // finalColor = vec4(tinted, finalColor.a);
}
