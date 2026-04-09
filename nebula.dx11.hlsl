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

float get_random(float2 uv, float min, float max)
{
  float ret = hash(uv);
  
  return ret * (max - min) + min;
}

float2 get_noise_displacement(float2 uv, float str, float freq)
{
  float2 displacement = float2(snoise(uv * freq), snoise(uv * 1.2345 * freq));
     
  return displacement * str;
}

float2 perturb(float2 uv, float str, float freq)
{
  return uv + get_noise_displacement(uv, str, freq);
}

float fbm(float2 uv, int octaves, int minOctaveDisplacement, float intensity)
{
  float amp = 1.0;
  float totalAmp = 0.0;
  float n = 0;
  
  for (int i = 0; i < octaves; i++)
  {
    float2 animUV = uv;
    if (i >= minOctaveDisplacement)
    {
      animUV = animUV + 0.5 * fGlobalTime * normalize(get_noise_displacement(animUV, intensity, 0.001));
    }
    n = n + amp * snoise(animUV);
    totalAmp += amp;
    uv *= 2.0;
    amp *= 0.5;
  }
  
  return n / totalAmp;  
}

float4 generate_star_layer(float2 uv, int layerIndex, float probStar)
{
  float gridSize = 10 + layerIndex * 5;
  
  float2 cellId = floor(uv * gridSize);
  
  if (hash(cellId + float2(12.34, 56.78)) > probStar)
    return float4(0,0,0,1);
  
  float2 cellUV = frac(uv * gridSize);
  float  radius = (5 - layerIndex) * 0.0025;

  float2 center = float2(get_random(cellId + float2(12.34, 56.78), radius, 1 - radius), get_random(cellId + float2(78.91, 523.45), radius, 1 - radius));
  
  
  float  v = length(cellUV - center);
  v = saturate(-(v - radius));
  
  v = (v > 0) ? (1) : (0);
  
  return float4(v,v,v,1);
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
	float2 uv = TexCoord;
  float aspect = v2Resolution.y / v2Resolution.x;
	uv /= float2(aspect, 1);

  float2 newUV = perturb(uv * 2, 0.6, 1.0);
  float n = fbm(newUV, 8, 4, 0.1) * 0.5 + 0.5;
  n = pow(n, 0.75);
  n = saturate(smoothstep(0.25, 1, n));
  
  float4 col = gradient1.Sample(smp, float2(n * 0.98 + 0.01, 0.5));
  
  float4 backgroundCol = lerp(float4(0,0,0,1), float4(col.xyz, 1), col.a);
  
  col = float4(0,0,0,0);
  for (int i = 0; i < 4; i++)
  {
    col += generate_star_layer(uv, i, 0.75) * (4 - i) * 0.25;
  }
  
  col = saturate(backgroundCol + col);
  
  return float4(col.rgb, 1);
}