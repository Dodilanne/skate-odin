#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform ivec3 palette[6];

out vec4 finalColor;

void main() {
    vec4 texelColor = texture(texture0, fragTexCoord)*fragColor;
    if (texelColor.a == 0.0) {
        finalColor = vec4(0.0);
        return;
    }

    vec3 color = texelColor.rgb*255.0;
    if (color.rgb == vec3(225.0, 230.0, 227.0)) { // shirt
        finalColor = vec4(palette[0]/255.0, 1.0);
    } else if (color.rgb == vec3(107.0, 164.0, 230.0)) { // pants
        finalColor = vec4(palette[1]/255.0, 1.0);
    } else if (color.rgb == vec3(88.0, 56.0, 6.0)) { // hair
        finalColor = vec4(palette[2]/255.0, 1.0);
    } else if (color.rgb == vec3(225.0, 169.0, 137.0)) { // skin
        finalColor = vec4(palette[3]/255.0, 1.0);
    } else if (color.rgb == vec3(37.0, 37.0, 37.0)) { // shoes
        finalColor = vec4(palette[4]/255.0, 1.0);
    } else if (color.rgb == vec3(1.0, 1.0, 1.0)) { // sole
        finalColor = vec4(palette[5]/255.0, 1.0);
    } else {
        finalColor = texelColor;
    }
}
