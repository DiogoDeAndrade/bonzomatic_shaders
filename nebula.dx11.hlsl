Texture2D texChecker;
Texture2D texNoise;
Texture2D texTex1;
Texture2D texTex2;
Texture2D texTex3;
Texture2D texTex4;
Texture2D gradient1;
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

float hash(float2 uv)
{
   return frac(sin(dot(uv, float2(123.4, 567.8))) * 1234.5678);
}

float snoise(float2 uv)
{
  float2 iuv = floor(uv);
  float2 fuv = frac(uv);
  
  fuv = fuv * fuv * fuv * (fuv * (fuv * 6 - 15) + 10);
  
  float a = hash(iuv);
  float b = hash(iuv + float2(1, 0));
  float c = hash(iuv + float2(0, 1));
  float d = hash(iuv + float2(1, 1));
  
  return lerp(lerp(a, b, fuv.x), lerp(c, d, fuv.x), fuv.y) * 2 - 1;
}

float fbm(float2 uv, int octaves)
{
  float amp = 1.0;
  float totalAmp = 0.0;
  float n = 0;
  
  for (int i = 0; i < octaves; i++)
  {
    n = n + amp * snoise(uv);
    totalAmp += amp;
    uv *= 2.0;
    amp *= 0.5;
  }
  
  return n / totalAmp;  
}

float2 perturb(float2 uv, float str, float freq)
{
  float2 displacement = float2(snoise(uv * freq), snoise(uv * 1.2345 * freq));
     
  return uv + displacement * str;
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
	float2 uv = TexCoord;
	uv /= float2(v2Resolution.y / v2Resolution.x, 1);

  float2 newUV = perturb(uv * 2, 0.6, 1.0);
  float n = fbm(newUV, 8) * 0.5 + 0.5;
  n = pow(n, 0.75);
  n = saturate(smoothstep(0.25, 1, n));
  
  float4 col = gradient1.Sample(smp, float2(n * 0.98 + 0.01, 0.5));
  
  col = lerp(float4(0,0,0,1), float4(col.xyz, 1), col.a);
  
  return float4(col.xyz, 1);
}