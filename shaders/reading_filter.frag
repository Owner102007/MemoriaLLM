// Светофильтр чтения.
//
// Ложится на страницу и только на неё: интерфейс остаётся нетронутым,
// файл не меняется. Порядок и все числа обязаны совпадать с эталонной
// реализацией `lib/domain/reading/reading_filter.dart` — она источник
// истины, а состав и порядок uniform-переменных проверяются тестом
// `test/reading/shader_contract_test.dart`.
//
// Требования `ImageFilter.shader`: первая переменная — vec2, её движок
// заполняет размером текстуры; первый sampler2D движок заполняет самой
// страницей.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uFilter;
uniform float uIntensity;
uniform float uBrightness;
uniform float uContrast;
uniform float uGamma;

uniform sampler2D uPage;

out vec4 fragColor;

// Rec. 709 — те же коэффициенты, что в проверке контраста тем.
const vec3 kLuminance = vec3(0.2126, 0.7152, 0.0722);

// Ниже какой насыщенности пиксель считается текстом, а не картинкой.
const float kSaturationLow = 0.10;
const float kSaturationHigh = 0.30;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
    // На OpenGL ES ось Y перевёрнута: без этого страница встанет на голову.
    uv.y = 1.0 - uv.y;
#endif

    vec4 src = texture(uPage, uv);
    float alpha = src.a;
    // Движок отдаёт цвет предумноженным на прозрачность; всю математику
    // ведём по чистому цвету и возвращаем предумножение в конце.
    vec3 color = alpha > 0.0 ? src.rgb / alpha : vec3(0.0);

    color = pow(clamp(color, 0.0, 1.0), vec3(uGamma));
    color = (color - 0.5) * uContrast + 0.5;

    int mode = int(uFilter + 0.5);
    float t = uIntensity;
    if (t > 0.0) {
        if (mode == 1) {
            // Ночной красный монохром.
            float lum = dot(color, kLuminance);
            color = mix(color, vec3(lum, 0.0, 0.0), t);
        } else if (mode == 2) {
            // Тёплый: снижение синего и чуть-чуть зелёного.
            color = mix(color, vec3(color.r, color.g * 0.88, color.b * 0.55), t);
        } else if (mode == 3) {
            // Сепия.
            vec3 sepia = vec3(
                dot(color, vec3(0.393, 0.769, 0.189)),
                dot(color, vec3(0.349, 0.686, 0.168)),
                dot(color, vec3(0.272, 0.534, 0.131)));
            color = mix(color, sepia, t);
        } else if (mode == 4) {
            // Инверсия с двойной инверсией картинок: цветной пиксель
            // инвертируется дважды, то есть остаётся собой, и фотографии
            // не превращаются в негативы.
            float high = max(max(color.r, color.g), color.b);
            float low = min(min(color.r, color.g), color.b);
            float picture = smoothstep(kSaturationLow, kSaturationHigh, high - low);
            color = mix(color, mix(1.0 - color, color, picture), t);
        }
    }

    color = clamp(color * uBrightness, 0.0, 1.0);
    fragColor = vec4(color * alpha, alpha);
}
