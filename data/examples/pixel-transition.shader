uniform texture2d prev_output_image;

uniform float color_transition_step_size<
    string label = "Color Transition Step Size";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 255.0;
    float step = 1.0;
> = 1;

uniform string notes<
    string widget_type = "info";
> = "This example demonstrates the use of the special cased texture2d 'prev_output_image`. \
It contains always the output image of the previous frame. This is used to transform every pixel \
to the new color separately. See milkglass-3x3.shader for a more complex example.";

float step(float current, float target) {
    if (current < target) {
        return min(current + color_transition_step_size / 255.0, target);
    } else {
        return max(current - color_transition_step_size / 255.0, target);
    }
}

float4 mainImage(VertData v_in) : TARGET
{
    float4 oldp = prev_output_image.Sample(textureSampler, v_in.uv);
    float4 newp = image.Sample(textureSampler, v_in.uv);

    newp.r = step(oldp.r, newp.r);
    newp.g = step(oldp.g, newp.g);
    newp.b = step(oldp.b, newp.b);
    newp.a = step(oldp.a, newp.a);
    
    return newp;
}
