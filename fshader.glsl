#version 450
in vec2 C;
out vec3 F;
/*layout (location=0)*/ uniform float A;

// Shader minifier does not (currently) minimize structs, so use short names.
// Using a one-letter name for the struct itself seems to trigger a bug, so use two.
struct ma {
    float A; // ambient
    float D; // diffuse
    float P; // specular
    float S; // shininess
    float R; // reflection
    vec3 C; // color
};

const ma blue_material = ma(0.1, 0.9, 0.8, 6.0, 0.3, vec3(0.5, 0.5, 1.0));
float FLOOR_GRID_SIZE = 0.8;

float origin_sphere(vec3 p, float radius) {
    return length(p) - radius;
}

float horizontal_plane(vec3 p, float height) {
    return p.y - height;
}

float origin_box(vec3 p, vec3 dimensions, float corner_radius) {
    vec3 a = abs(p);
    return length(max(abs(p) - dimensions, 0.0)) - corner_radius;
}

float csg_subtraction(float dist1, float dist2) {
    return max(dist1, -dist2);
}

void closest_material(inout float dist, inout ma mat, float new_dist, ma new_mat) {
    if (new_dist < dist) {
        dist = new_dist;
        mat = new_mat;
    }
}

float center_mod(float v, float m) {
    return mod(v - 0.5 * m, m) - 0.5 * m;
}

float center_div(float v, float m) {
    return v - 0.5 * m - center_mod(v, m);
}

const float ONE_SIXTH = 1.0/6.0;
const float ONE_THIRD = 1.0/3.0;
const float TWO_THIRDS = 2.0/3.0;

float tcolor(float tc, float q, float p) {
    if (tc < ONE_SIXTH) {
        return p * 6 * (q - p) * tc;
    } else if (tc < 0.5) {
        return q;
    } else if (tc < TWO_THIRDS) {
        return p + 6 * (q - p) * (TWO_THIRDS - tc);
    } else {
        return p;
    }
}

vec3 hsl_to_rgb(float h, float s, float l) {
    if (s <= 0) {
        // grayscale
        return vec3(l);
    }
    float q;
    if (l < 0.5) {
        q = l * (1 + s);
    } else {
        q = l + s - l * s;
    }
    float p = 2 * l - q;
    float tr = mod(h + ONE_THIRD, 1.0);
    float tg = h;
    float tb = mod(h + TWO_THIRDS, 1.0);
    return vec3(
        tcolor(tr, q, p),
        tcolor(tg, q, p),
        tcolor(tb, q, p));
}

float sin01(float x) {
    return 0.5 + sin(x) * 0.5;
}

ma floor_material(vec3 p) {
    float xdiv = center_div(p.x, FLOOR_GRID_SIZE) / FLOOR_GRID_SIZE;
    float zdiv = center_div(p.z, FLOOR_GRID_SIZE) / FLOOR_GRID_SIZE;
    float hue = sin01(0.1 + xdiv * 1.3 + zdiv * 3.3);
    float saturation = 0.3 + 0.7 * sin01(xdiv * 9.1 + zdiv * 2.1);
    float lightness = 0.3 + 0.5 * sin01(xdiv * 3.3 + zdiv * 8.1);
    vec3 col = hsl_to_rgb(hue, saturation, lightness);
    return ma(0.1, 0.9, 0.8, 10.0, 0.1, col);
}

float repeated_boxes_xyz(vec3 p, vec3 dimensions, float corner_radius, vec3 modulo) {
    vec3 q = mod(p - 0.5 * modulo, modulo) - 0.5 * modulo;
    return origin_box(q, dimensions, corner_radius);
}

float repeated_boxes_xz(vec3 p, vec3 dimensions, float corner_radius, float modulo, float height) {
    vec3 q = vec3(
        center_mod(p.x, modulo),
        p.y - height,
        center_mod(p.z, modulo));
    return origin_box(q, dimensions, corner_radius);
}

float tiles(vec3 p) {
    return repeated_boxes_xz(p, vec3(FLOOR_GRID_SIZE * 0.42), FLOOR_GRID_SIZE * 0.07, FLOOR_GRID_SIZE, -2);
}

float fancy_object(vec3 p) {
    float sphere_size = 1.5;
    float hollow_sphere = csg_subtraction(
        origin_sphere(p, sphere_size),
        origin_sphere(p, sphere_size * 0.98));
    float grid_size = 0.2;
    return csg_subtraction(
        hollow_sphere,
        repeated_boxes_xyz(p, vec3(grid_size * 0.4), grid_size * 0.05, vec3(grid_size)));
}

float twisted_object(vec3 p) {
    float amount = 0.3;
    float c = cos(amount * p.y);
    float s = sin(amount * p.y);
    mat2 m = mat2(c, -s, s, c);
    vec3 q = vec3(m * p.xz, p.y);
    return fancy_object(q);
}

float floor_plane(vec3 p) {
    return horizontal_plane(p, -1.0);
}

float scene(vec3 p) {
    float dist = twisted_object(p);
    dist = min(dist, tiles(p));
    return dist;
}

ma scene_material(vec3 p) {
    float dist = origin_sphere(p, 1.0); // optimization
    ma mat = blue_material;
    closest_material(dist, mat, floor_plane(p), floor_material(p));
    return mat;
}

bool ray_march(inout vec3 p, vec3 direction) {
    float total_dist = 0.0;
    for (int i = 0; i < 200; i++) {
        float dist = scene(p);
        if (dist < 0.001) {
            return true;
        }
        total_dist += dist;
        if (total_dist > 10.0) {
            return false;
        }
        p += direction * dist;
    }
    return false;
}

vec3 estimate_normal(vec3 p) {
    float epsilon = 0.001;
    return normalize(vec3(
        scene(vec3(p.x + epsilon, p.y, p.z)) - scene(vec3(p.x - epsilon, p.y, p.z)),
        scene(vec3(p.x, p.y + epsilon, p.z)) - scene(vec3(p.x, p.y - epsilon, p.z)),
        scene(vec3(p.x, p.y, p.z + epsilon)) - scene(vec3(p.x, p.y, p.z - epsilon))
    ));
}

vec3 ray_reflection(vec3 direction, vec3 normal) {
    return 2.0 * dot(-direction, normal) * normal + direction;
}

float soft_shadow(vec3 p, vec3 light_direction, float sharpness) {
    p += light_direction * 0.1;
    float total_dist = 0.1;
    float res = 1.0;
    for (int i = 0; i < 20; i++) {
        float dist = scene(p);
        if (dist < 0.01) {
            return 0.0;
        }
        total_dist += dist;
        res = min(res, sharpness * dist / total_dist);
        if (total_dist > 10.0) {
            break;
        }
        p += light_direction * dist;
    }
    return res;
}

const vec3 background_color = vec3(0.8, 0.9, 1.0);

vec3 apply_fog(vec3 color, float total_distance) {
    return mix(color, background_color, min(1.0, total_distance / 10.0));
}

vec3 phong_lighting(vec3 p, ma mat, vec3 ray_direction) {
    vec3 normal = estimate_normal(p);
    vec3 light_direction = normalize(vec3(-0.3, -1.0, -0.5));
    float shadow = soft_shadow(p, -light_direction, 20.0);
    float diffuse = max(0.0, mat.D * dot(normal, -light_direction)) * shadow;
    vec3 reflection = ray_reflection(ray_direction, normal);
    float specular = pow(max(0.0, mat.P * dot(reflection, -light_direction)), mat.S) * shadow;
    return mat.C * (diffuse + mat.A) + vec3(specular);
}

vec3 apply_reflections(vec3 color, ma mat, vec3 p, vec3 direction) {
    float reflection = mat.R;
    for (int i = 0; i < 5; i++) {
        if (reflection <= 0.01) {
            break;
        }
        vec3 reflection_color = background_color;
        direction = ray_reflection(direction, estimate_normal(p));
        p += 0.05 * direction;
        if (ray_march(p, direction)) {
            reflection_color = phong_lighting(p, scene_material(p), direction);
            color = mix(color, reflection_color, reflection);
            mat = scene_material(p);
            reflection *= mat.R;
        } else {
            color = mix(color, reflection_color, reflection);
            break;
        }
    }
    return color;
}

void main() {
    float u = C.x - 1.0;
    float v = (C.y - 1.0) / A;
    vec3 eye_position = vec3(0.0, 1.0, 3.0);
    vec3 forward = normalize(-eye_position);
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, forward));
    up = cross(-right, forward);
    float focal_length = 1.0;
    vec3 start_pos = eye_position + forward * focal_length + right * u + up * v;
    vec3 direction = normalize(start_pos - eye_position);
    vec3 p = start_pos;
    F = background_color;
    if (ray_march(p, direction)) {
        ma mat = scene_material(p);
        F = phong_lighting(p, mat, direction);
        F = apply_reflections(F, mat, p, direction);
        F = apply_fog(F, length(p - start_pos));
    }
}
