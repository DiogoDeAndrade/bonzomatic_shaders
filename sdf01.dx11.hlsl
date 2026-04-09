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
#define MAX_ITER 100

cbuffer constants
{
	float fGlobalTime;    // in seconds
	float2 v2Resolution;  // viewport resolution (in pixels)
	float fFrameTime;     // duration of the last frame, in seconds
}

float4 plas( float2 v, float time )
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return float4( sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float sd_box(float3 p, float3 b)
{
    float3 d = abs(p) - b;
    return length(max(d,0.0)) + min(max(d.x, max(d.y,d.z)),0.0);
}

float sd_sphere(float3 p, float radius)
{
  return length(p) - radius;
}

float op_union(float a, float b)
{
    return min(a,b);
}
float op_subtraction( float a, float b )
{
    return max(a,-b);
}
float op_intersection( float a, float b )
{
    return max(a,b);
}

float3 transform_rotateY(float3 p, float angle)
{
  float3 ret = p;
  float c = cos(angle);
  float s = sin(angle);
  
  ret.x = c * p.x + s * p.z;
  ret.z = c * p.z - s * p.x;
  
  return ret;
}

float scene(float3 p)
{
  float3 p1 = transform_rotateY(p, fGlobalTime);
  return op_subtraction(
    sd_box(p1, float3(3,3,3)),
    sd_sphere(p1, 4));
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
  float aspect = v2Resolution.x / v2Resolution.y;

  float2 uv = TexCoord * 2 - 1;
  uv.x *= aspect;
  
	float4 col = 0;
  
  float fovY = PI / 2;
  float t = tan(fovY * 0.5);
  float fovX = fovY * aspect;
  float3 currentPos = float3(0, 0, -10);
  float3 currentDir = normalize(float3(uv.x * t, uv.y * t, 1));
  
  for (int i = 0; i < MAX_ITER; i++)
  {
    float d = scene(currentPos);
    if (d < 1e-3)
    {
      // Got inside
      col = float4(1,1,1,1);
      break;
    }
    else
    {
      currentPos += currentDir * d;
    }
  }
  
  if (i == MAX_ITER) col = plas(uv * 0.1, 0.1 * fGlobalTime);
  
	return col;
}