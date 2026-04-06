Texture2D texChecker;
Texture2D texNoise;
Texture2D texTex1;
Texture2D texTex2;
Texture2D texTex3;
Texture2D texTex4;
Texture1D texFFT; // towards 0.0 is bass / lower freq, towards 1.0 is higher / treble freq
Texture1D texFFTSmoothed; // this one has longer falloff and less harsh transients
Texture1D texFFTIntegrated; // this is continually increasing
Texture2D texPreviousFrame; // screenshot of the previous frame
SamplerState smp;

cbuffer constants
{
	float fGlobalTime; // in seconds
	float2 v2Resolution; // viewport resolution (in pixels)
	float fFrameTime; // duration of the last frame, in seconds
}

float3 HSVtoRGB(float h, float s, float v)
{
    float3 rgb = clamp(abs(frac(h + float3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return v * lerp(float3(1.0, 1.0, 1.0), rgb, s);
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
	float2 uv = TexCoord;
	uv -= 0.5;
	uv /= float2(v2Resolution.y / v2Resolution.x, 1);
  
  float2 origUV = uv;
  
  uv.x += 0.1 * cos(uv.y * 50 + fGlobalTime * 0.5);
  uv.y += 0.15 * cos(uv.x * 33 + fGlobalTime * 0.66);
	
  // Convert UV to polar
  float r = frac(0.5 * (length(uv) - fGlobalTime * 1.0));
  float a = atan(uv.y/uv.x) + fGlobalTime * 0.9;
 
  float2 v = float2(cos(fGlobalTime), sin(fGlobalTime));
  float vdpX = dot(v, origUV);
  float vdpY = dot(float2(-v.y, v.x), origUV);
  
  if (vdpX < 0) r = 1 - r;
  if (vdpY < 0) r = 1 - r;
	float4 col = float4(HSVtoRGB(r, 0.6, 0.5), 1);
  
  return col;
}