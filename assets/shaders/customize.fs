#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform sampler2D palettes;

out vec4 finalColor;

void main() {
    vec4 texel = texture(texture0, fragTexCoord);

    if (fragColor.a != 0) {
        finalColor = texel*fragColor;
        return;
    }

    int skaterId = int(fragColor.r * 255.0 + 0.5);

    vec4 first = texelFetch(palettes, ivec2(skaterId*6, 0), 0);
    if (first.a == 0.0) {
        finalColor = texel;
        return;
    }

    for (int i = 0; i < 5; i++) {
        vec3 orig = texelFetch(palettes, ivec2(i, 0), 0).rgb;
        if (texel.rgb == orig) {
            vec3 color = texelFetch(palettes, ivec2((skaterId * 6) + i, 0), 0).rgb;
            finalColor = vec4(color, 1.0);
            return;
        }
    }

    finalColor = texel;
    return;
}
