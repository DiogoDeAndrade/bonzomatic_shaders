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

#define PI 3.141592
#define MAX_ITER 200

cbuffer constants
{
	float fGlobalTime; // in seconds
	float2 v2Resolution; // viewport resolution (in pixels)
	float fFrameTime; // duration of the last frame, in seconds
}

float4 plas( float2 v, float time )
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return float4( sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float hash(float3 p)
{
  return frac(sin(dot(p, float3(12.3412, 34.1234, 21.3565))) * 45678.9123);
}

float noise3d(float3 p)
{
  float3 ip = floor(p);
  float3 fp = frac(p);
  
  fp = fp * fp * fp * (fp * (fp * 6 - 15) + 10);
  
  float p1 = hash(ip + float3(0, 0, 0));
  float p2 = hash(ip + float3(1, 0, 0));
  float p3 = hash(ip + float3(0, 1, 0));
  float p4 = hash(ip + float3(1, 1, 0));

  float p5 = hash(ip + float3(0, 0, 1));
  float p6 = hash(ip + float3(1, 0, 1));
  float p7 = hash(ip + float3(0, 1, 1));
  float p8 = hash(ip + float3(1, 1, 1));
  
  float x1 = lerp(p1, p2, fp.x);
  float x2 = lerp(p3, p4, fp.x);

  float x3 = lerp(p5, p6, fp.x);
  float x4 = lerp(p7, p8, fp.x);
  
  float y1 = lerp(x1, x2, fp.y);
  float y2 = lerp(x3, x4, fp.y);
  
  return lerp(y1, y2, fp.z);
}

float fbm(float3 pos, int octaves, float amplitude, float freq)
{
  float a = amplitude;
  float f = freq;
  float ret = 0;
  
  for (int i = 0; i < octaves; i++)
  {
    ret += a * noise3d(pos * f);
    a *= 0.5;
    f *= 2;
  }
  
  return ret;
}

struct SdfResult
{
  float3  currentPos;
  float   dist;
  float3  closestPoint;
};

SdfResult make_result(float3 currentPos, float dist, float3 closestPoint = float3(1000, 1000, 1000))
{
  SdfResult ret;
  ret.currentPos = currentPos;
  ret.dist = dist;
  ret.closestPoint = closestPoint;
  return ret;  
}

SdfResult sd_sphere(float3 pos, float3 center, float radius)
{
  float3 d = pos - center;
  return make_result(pos, length(d) - radius, center + d * radius);
}

SdfResult sd_displace3d(SdfResult p, float amplitude, float freq)
{
  return make_result(p.currentPos, p.dist + fbm(p.currentPos, 8, -amplitude, freq), p.currentPos);
}

float fft_band_avg(Texture1D tex, int s, int e)
{
    float v = 0.0;
    for (int j = s; j < e; j++)
        v += tex.Load(int2(j, 0)).x;
    return v / (e - s);
}

SdfResult scene(float3 pos)
{
    float bass = 0.0;
    int j;
    for (j = 1; j < 8; j++)
        bass += texFFTSmoothed.Load(int2(j, 0)).x;
    bass /= 7.0;

    float hit = 0.0;
    for (j = 1; j < 8; j++)
    {
        float raw = texFFT.Load(int2(j, 0)).x;
        float sm  = texFFTSmoothed.Load(int2(j, 0)).x;
        hit += max(0.0, raw - sm);
    }
    hit /= 7.0;

    float amp = 0.2 + 1.5 * bass + 3.0 * hit;

    return sd_displace3d(
        sd_sphere(pos, float3(0,0,0), 2.0),
        amp,
        0.26
    );
}

float3 compute_normal(SdfResult data, float3 pos)
{
  float eps = 1e-3;
  float dx = data.dist - scene(pos + float3(eps,0,0)).dist;
  float dy = data.dist - scene(pos + float3(0,eps,0)).dist;
  float dz = data.dist - scene(pos + float3(0,0,eps)).dist;
  
  return -normalize(float3(dx, dy, dz));
}

float3 compute_lighting(SdfResult data, float3 surfacePoint)
{
  float3 toLight = normalize(float3(2,2,-1));
  float3 normal = compute_normal(data, surfacePoint); 
  float dp = max(0, dot(toLight, normal)) + 0.03;
  
  return float3(1,1,1) * dp;
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{  
	float2 uv = TexCoord;
	uv -= 0.5;
	uv /= float2(v2Resolution.y / v2Resolution.x, 1);

  float   fov = PI / 2.0;
  float   tanFoV = tan(fov * 0.5);
  float3  currentPos = float3(0,0,-20);
  float3  dir = normalize(float3(uv.x * tanFoV, uv.y * tanFoV, 1));
  
  for (int i = 0; i < MAX_ITER; i++)
  {
    SdfResult res = scene(currentPos);
    if (res.dist < 1e-3)
    {
      return float4(compute_lighting(res, currentPos), 1);
    }
    else
    {
      currentPos += dir * res.dist;
    }
  }
  
  return float4(0,0,0,1);
}
