// prev_output_image is a special cased texture2d which always contains
// the result of the last render pass. It is used to retain some state 
// so we can create a more stable final color.
uniform texture2d prev_output_image;

uniform string Description<
    string widget_type = "info";
> = "Calculates a simple 3x3 color grid based on the source image. It can \
record colors up to 40 seconds to provide stable colors. It can be used as \
ambient color for your background overlay or to hide your screen without \
turning your stream black. See configuration instructions below.";

uniform float4 bright_color<
    string label = "Bright Color";
> = {0.188, 0.58, 1.0, 1};

uniform float lumaMax<
    string label = "Luma Max";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.001;
> = 0.55;

uniform float4 dark_color<
    string label = "Dark Color";
> = {0.043, 0.1372, 0.2392, 1};

uniform string dark_hint<
    string widget_type = "info";
    string label = " ";
> = "Used when the color is above the maximum luminance.";

uniform float lumaMin<
    string label = "Luma Min";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.001;
> = 0.05;

uniform string bright_hint<
    string widget_type = "info";
    string label = " ";
> = "Used when the color is below the minimum luminance.";

uniform string limit_hint<
    string widget_type = "info";
    string label = " ";
> = "If you want to apply the luminance limits to the history \
values or on the final value. This may need experimentation on your \
side, but only final value should be enough:";

uniform bool limit_history_value<
    string label = "Luma limit: history value";
    string widget_type = "checkbox";
>= false;

uniform bool limit_final_value<
    string label = "Luma limit: final value";
    string widget_type = "checkbox";
>= true;

uniform string seconds_hint<
    string widget_type = "info";
    string label = " ";
> = "You can stabilize the generated color by using the history values. \
The history can contain color values. Up to 2400 frames, resulting in \
a total of 40 seconds.";

uniform float seconds<
    string label = "Seconds (60 FPS)";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 40.0;
    float step = 0.0166;
> = 3;

uniform bool ignore_alpha_for_output<
    string label = "Set alpha value to 1 for output colors";
    string widget_type = "checkbox";
>= true;

uniform string Guide<
    string widget_type = "info";
> = "1. Create a new 'Color Source' with a full transparent black color.\n\
2. Open the filters settings of this new 'Color Source'.\n\
3. Add a new filter 'User definied shader' named 'Copy', check 'Load shader text from file' and selected 'Add.shader' from the examples folder. \
Select on the line 'other image' your source which you want to create the background from.\n\
4. Add a new filter 'Scaling/Aspect Ratio' with resolution '284x160', which will significantly reduce GPU load.\n\
5. Add a another 'User defined shader' named 'milkglass 3x3', check 'Load shader text from file' and pick 'milkglass-3x3.shader' from the examples folder. \
Keep the other setting as they are for now.\n\
6. Add a new filter 'Crop/Pad' named 'Pick stable colors'. Uncheck the relative checkbox and set X: 5, Y: 5, Width: 3, Height: 3.\n\
7. Now you can see how the colors are changing over time. If you right-click on the 'Color Source' and change \
the 'Scale Filtering' to 'Bicubic', you can get an even nicer gradient. If you set the it to 'Point' or 'Area' you can see the actual colors.\n\
8. In the 'milkglass 3x3' shader you can adjust some settings to your use case. For example, you can make it more or less stable by adjusting the 'Seconds' parameter. \
If you have it set to 0 seconds, it only takes the colors of the current frame. The higher the value, the more frames it will use to stabilize the final colors. This \
reduces flickering of the background when small portions on the screens are getting suddenly bright.";

float4 calculateNewPixel(int pixelX, int pixelY) 
{
    // Calculate the start and end range for X axis.
    float tileWidth = uv_size.x / 3.0;
    float tileHeight = uv_size.y / 3.0;
    int xStart = int(pixelX * tileWidth);
    int xEnd = int((pixelX + 1) * tileWidth);
    int yStart = int(pixelY * tileHeight);
    int yEnd = int((pixelY + 1) * tileHeight);

    // The full color value is always centered within the pixel. 
    // Therefore, 0.5, 0.5 represents the top-left corner with the fully colored pixel. 
    // If 0.0, 0.0 was chosen, it would look half-transparent.
    float widthMinus1 = uv_size.x - 1;
    float heightMinus1 = uv_size.y - 1;
    float xOffset = 0.5 / uv_size.x;
    float yOffset = 0.5 / uv_size.y;

    // Prepare variables for averaging values.
    float transparent = 0.0;
    int count = 0;
    float samples = 0.0;
    float4 c = float4(0.0, 0.0, 0.0, 0.0);

    // Iterate over all pixels in the current tile and
    // fill values for the average beforehand.
    [loop] for (int y = int(yStart); y < yEnd; y++) {
        float yf = float(y) / uv_size.y + yOffset;
    	[loop] for (int x = int(xStart); x < xEnd; x++) {
            float xf = float(x) / uv_size.x + xOffset;
            float4 sc = image.Sample(textureSampler, float2(xf, yf));

            transparent += sc.a;
			count++;
            c += sc * sc.a;
            samples += sc.a;
        }
    }

    // Create an average for the opaque color value
    if (samples > 0.0)
        c /= samples;

    // Adjust the transparency value separately
    if (count > 0)
        transparent = transparent / float(count); 
    else
        transparent = 1;
    
    c.a = transparent;

    // This block recolorss dark and bright areas.
    if (limit_history_value)
    {
        float luminance = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;

        if (luminance < lumaMin) {
            c.rgb = lerp(dark_color.rgb, c.rgb, luminance / lumaMin);
        } else if (luminance > lumaMax) {
            c.rgb = lerp(c.rgb, bright_color.rgb, (luminance - lumaMax) / (1.0 - lumaMax));
        }
    }

    return c;
}

float4 combineHistory(int pixelX, int pixelY) 
{
    if (seconds == 0) {
        float4 result = calculateNewPixel(pixelX - 5, pixelY - 5);
        if (ignore_alpha_for_output) {
            result.a = 1;
        }
        return result;
    }

    // Calculate the relative pixel position within the tile
    pixelX -= 5;
    pixelY += 5;

    // The full color value is always in the center of the pixel. 
    // So 0.5, 0.5 is the top left corner with the fully colored pixel. 
    // If 0.0, 0.0 was chosen, it would look half-transparent.
    float xOffset = 0.5 / uv_size.x;
    float yOffset = 0.5 / uv_size.y;
    int maxCount = int(seconds * 60);

    // Prepare variables for averaging values.
    float transparent = 0.0;
    int count = 0;
    float samples = 0.0;
    float4 c = float4(0.0, 0.0, 0.0, 0.0);

    // Iterate over all pixels in the current tile and
    // fill values for the average beforehand.
    [loop] for (int y = 0; y < 48 && count < maxCount; y++) {
        float yf = float(y * 3 + pixelY) / uv_size.y + yOffset;
    	[loop] for (int x = 0; x < 50 && count < maxCount; x++) {
            float xf = float(x * 3 + pixelX) / uv_size.x + xOffset;
            float4 sc = prev_output_image.Sample(textureSampler, float2(xf, yf));

            transparent += sc.a;
			count++;
            c += sc * sc.a;
            samples += sc.a;
        }
    }

    // Create an average for the opaque color value
    if (samples > 0.0)
        c /= samples;

    // Adjust the transparency value separately
    if (count > 0 && !ignore_alpha_for_output)
        transparent = transparent / float(count);
    else
        transparent = 1;

    c.a = transparent;

    // This block recolorss dark and bright areas.
    if (limit_final_value)
    {
        float luminance = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;

        if (luminance < lumaMin) {
            c.rgb = lerp(dark_color.rgb, c.rgb, luminance / lumaMin);
        } else if (luminance > lumaMax) {
            c.rgb = lerp(c.rgb, bright_color.rgb, (luminance - lumaMax) / (1.0 - lumaMax));
        }
    }

    return c;
}

float4 executeMove(int pixelX, int pixelY)
{
    if (pixelX <= 2)
    {
        // We are already on the most left side. Go one row up.
        pixelX = 153 + pixelX;
        pixelY -= 3;
    }
    else 
    {
        // Select the pixels in the tile to the left.
        pixelX -= 3;
    }

    float xOffset = 0.5 / uv_size.x;
    float yOffset = 0.5 / uv_size.y;

    float xf = float(pixelX) / uv_size.x + xOffset;
    float yf = float(pixelY) / uv_size.y + yOffset;
    return prev_output_image.Sample(textureSampler, float2(xf, yf));
}

float4 mainImage(VertData v_in) : TARGET
{
    int pixelX = int(v_in.uv.x * uv_size.x);
	int pixelY = int(v_in.uv.y * uv_size.y);
    // The 3x3 pixels between (5,5) and (7,7) contain the stable colours.
    // These colours are calculated using the average value of the entire 3x3 tiles within
    // the history between (5,10) and (155,153) = 2400 frames / 60 = 40 sec.
    if (pixelX >= 5 && pixelX <= 7 && pixelY >= 5 && pixelY <= 7)
        return combineHistory(pixelX, pixelY);
    
    // Area that is not used and is always empty
    if (pixelY < 10 || pixelX > 155 || pixelY > 153 || seconds == 0)
        return float4(0,0,0,0);

    // The first tile always contains the colours of the latest frame.
    if (pixelY >= 10 && pixelY <= 12 && pixelX >= 0 && pixelX <= 2)
        return calculateNewPixel(pixelX, pixelY - 10);

    return executeMove(pixelX, pixelY);
}
