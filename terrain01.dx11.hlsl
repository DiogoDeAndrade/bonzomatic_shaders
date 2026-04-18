Texture2D gradient1;
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

#define PI 3.1451592
#define MAX_ITER 500

float hash(float2 pos)
{
  return frac(34567.2313 * sin(12.34 * pos.x + 21.33 * pos.y));
}

float hash(float3 pos)
{
  return frac(34567.2313 * sin(12.34 * pos.x + 21.33 * pos.y + 34.79 * pos.z));
}

float noise2d(float2 pos)
{
  float2 ip = floor(pos);
  float2 fp = frac(pos);
  
  fp = fp * fp * fp * (fp * (fp * 6 - 15) + 10);
  
  float  p1 = hash(ip + float2(0,0));
  float  p2 = hash(ip + float2(1,0));
  float  p3 = hash(ip + float2(0,1));
  float  p4 = hash(ip + float2(1,1));
  
  float x1 = lerp(p1, p2, fp.x);
  float x2 = lerp(p3, p4, fp.x);
  
  return lerp(x1, x2, fp.y);
}

float noise3d(float3 pos)
{
  float3 ip = floor(pos);
  float3 fp = frac(pos);
  
  fp = fp * fp * fp * (fp * (fp * 6 - 15) + 10);
  
  float  p1 = hash(ip + float3(0,0,0));
  float  p2 = hash(ip + float3(1,0,0));
  float  p3 = hash(ip + float3(0,1,0));
  float  p4 = hash(ip + float3(1,1,0));
  float  p5 = hash(ip + float3(0,0,1));
  float  p6 = hash(ip + float3(1,0,1));
  float  p7 = hash(ip + float3(0,1,1));
  float  p8 = hash(ip + float3(1,1,1));
  
  float x1 = lerp(p1, p2, fp.x);
  float x2 = lerp(p3, p4, fp.x);
  float x3 = lerp(p5, p6, fp.x);
  float x4 = lerp(p7, p8, fp.x);
  float y1 = lerp(x1, x2, fp.y);
  float y2 = lerp(x3, x4, fp.y);
  
  return lerp(y1, y2, fp.z);
}

float fbm3d(float3 pos, int octaves, float amp, float freq)
{
  float ret = 0;
  float a = amp;
  float f = freq;
  
  for (int i = 0; i < octaves; i++)
  {
    ret += a * noise3d(pos * f);
    a *= 0.5;
    f *= 2.0;
  }
  
  return ret;
}

float fbm2d(float2 pos, int octaves, float amp, float freq)
{
  float ret = 0;
  float a = amp;
  float f = freq;
  
  for (int i = 0; i < octaves; i++)
  {
    ret += a * (noise2d(pos * f) * 2 - 1);
    a *= 0.5;
    f *= 2.0;
  }
  
  return ret;
}

struct SdfResult
{
  float     dist;
};

SdfResult make_result(float dist)
{
  SdfResult res;
  res.dist = dist;
  return res;
}

SdfResult sd_sphere(float3 pos, float3 center, float radius)
{
  return make_result(length(pos - center) - radius);
}

SdfResult sd_plane(float3 pos, float3 normal, float d)
{
  return make_result(dot(pos, normal) - d);
}

SdfResult sd_displace2d(float3 pos, SdfResult input, float freq, float amplitude)
{
  float offset = fbm2d(pos.xz, 4, amplitude, freq);
  return make_result(input.dist - offset);
}

SdfResult fluffify(float3 pos, SdfResult input, float freq, float thickness, bool computeNormals)
{
    if (computeNormals) return input;

    float d = input.dist;

    // Keep the solid object interior unchanged
    if (d < 0.0)
        return input;

    // Outside fur region: unchanged
    if (d > thickness)
        return input;

    // Shell depth: 1 near surface, 0 at fur tip
    float shell = 1.0 - d / thickness;

    float r = noise3d(pos * freq);

    // Fur gets sparser toward the tips
    float threshold = lerp(0.8, 0.1, shell);

    if (r > threshold)
        return make_result(d);

    // Push surface outward in occupied fur regions
    return make_result(d - 0.15 * shell);
}

SdfResult scene(float3 pos, bool computeNormals = false)
{
  SdfResult terrain = sd_displace2d(
                        pos, 
                        sd_plane(pos, float3(0,1,0), -6), 
                        0.05, 4);
  
  //return fluffify(pos, sd_sphere(pos, float3(0,0,0), 2), computeNormals);
  return fluffify(pos, terrain, 5, 0.2, computeNormals);
}

float4 plas( float2 v, float time )
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return float4( sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float3 compute_normal(float3 pos, SdfResult res)
{
  float eps = 1e-2;
  res = scene(pos, true);
  float dx = res.dist - scene(pos + float3(eps, 0, 0), true).dist;
  float dy = res.dist - scene(pos + float3(0, eps, 0), true).dist;
  float dz = res.dist - scene(pos + float3(0, 0, eps), true).dist;
  
  return -normalize(float3(dx, dy, dz));
}

float3 compute_light(float3 pos, SdfResult res)
{
  //float3 toLight = normalize(float3(cos(fGlobalTime),1,sin(fGlobalTime)));
  float3 toLight = normalize(float3(cos(0.1),1,sin(0.1)));
  float3 normal = compute_normal(pos, res);
  
  float dp = dot(normal, toLight);
  
  dp = max(dp, 0) + max(-dp, 0) * 0.05;
  
  return float3(0.3, 0.6, 0.3) * dp;
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
	float2 uv = TexCoord;
	uv -= 0.5;
  uv.x *= (v2Resolution.x / v2Resolution.y);
  
  float fov = PI / 2;
  float t = tan(fov * 0.5);
  
  float3 origin = float3(0,0,-10 + fGlobalTime * 10);
  origin.y = fbm2d(origin.xz, 4, 4, 0.05);
  float3 dir = normalize(float3(t * uv.x, t * uv.y, 1));
  
  float3 pos = origin;
  
  float3 col = float3(0,0,0);
  
  for (int i = 0; i < MAX_ITER; i++)
  {
    SdfResult r = scene(pos);
    if (r.dist < 1e-3)
    {
      col = compute_light(pos, r);
      break;
    }
    else
    {
      pos = pos + dir * r.dist * 0.9;
    }
  }

	return float4(col, 1);
}