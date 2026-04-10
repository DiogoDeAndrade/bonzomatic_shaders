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
	float fGlobalTime;    // in seconds
	float2 v2Resolution;  // viewport resolution (in pixels)
	float fFrameTime;     // duration of the last frame, in seconds
}

struct Material
{
  int    type;
  float4 color;
};

Material make_material(float4 color, int type = 0)
{
    Material m;
    m.type = type;
    m.color = color;
    return m;
}

float4 checkboard_pattern(float3 pos)
{
  int3 ip = floor(pos * 0.25);
  
  if (((ip.x + ip.z) % 2) == 0)
    return float4(0,1,1,1);
  else
    return float4(0,0,1,1);
}

float4 material_get_color(float3 pos, Material mat)
{
  if (mat.type == 0) 
    return mat.color;
  else
    return checkboard_pattern(pos);
}

struct SdfResult
{
    float dist;
    Material mat;
};

SdfResult make_result(float d, Material material)
{
    SdfResult r;
    r.dist = d;
    r.mat = material;
    return r;
}

#define RED_MATERIAL    make_material(float4(1, 0, 0, 1));
#define GREEN_MATERIAL  make_material(float4(0, 1, 0, 1));

float4 plas( float2 v, float time)
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return float4(sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

SdfResult sd_box(float3 p, float3 b, Material material)
{
    float3 d = abs(p) - b;
    return make_result(length(max(d,0.0)) + min(max(d.x, max(d.y,d.z)),0.0), material);
}

SdfResult sd_sphere(float3 p, float radius, Material material)
{
  return make_result(length(p) - radius, material);
}

SdfResult sd_plane(float3 p, float3 normal, float d, Material material)
{
  return make_result(dot(p, normal) + d, material);
}

SdfResult op_union(SdfResult a, SdfResult b)
{
  if (a.dist < b.dist) 
  {
    return a;
  }
  else
  {
    return b;
  }
}

SdfResult op_subtraction(SdfResult a, SdfResult b)
{
  if (a.dist > -b.dist) 
  {
    return a;
  }
  else
  {
    return make_result(-b.dist, a.mat);
  }
}

SdfResult op_intersection(SdfResult a, SdfResult b)
{
  if (a.dist > b.dist) 
  {
    return a;
  }
  else
  {
    return b;
  }
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

SdfResult scene(float3 p)
{
  float3 p1 = transform_rotateY(p, fGlobalTime);
  return 
    op_union(
      op_subtraction(
        sd_box(p1, float3(3,3,3), make_material(float4(1, 0, 0, 1))),
        sd_sphere(p1, 4, make_material(float4(0, 1, 0, 1)))
      ),
      sd_plane(p1, float3(0, 1, 0), 3, make_material(float4(1, 1, 0, 1), 1))
    );
}

float3 compute_normal(SdfResult r, float3 p)
{
  float eps = 0.001;
  float dx = scene(p + float3(eps, 0, 0)).dist - r.dist;
  float dy = scene(p + float3(0, eps, 0)).dist - r.dist;
  float dz = scene(p + float3(0, 0, eps)).dist - r.dist;
  
  float3 n = float3(dx, dy, dz);
  
  return normalize(n);
}

float4 compute_lighting(float3 pos, float3 normal, SdfResult r)
{
  float  ambient_light = 0.2f;
  float3 light_pos = float3(-4, 5, 0);
  float3 toLight = normalize(light_pos - pos);
  float dt = max(0, dot(toLight, normal));
  
  return float4((ambient_light + dt) * material_get_color(pos, r.mat).rgb, 1);
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
    SdfResult current = scene(currentPos);
    if (current.dist < 1e-3)
    {
      // Got inside
      float3 normal = compute_normal(current, currentPos);
      //col = float4(normal.xyz * 0.5 + 0.5, 1);
      //col = current.mat.color;
      
      col = compute_lighting(currentPos, normal, current);

      break;
    }
    else
    {
      currentPos += currentDir * max(current.dist * 0.9, 0.01);
    }
  }
  
  if (i == MAX_ITER) col = plas(uv * 0.1, 0.1 * fGlobalTime);
  
	return col;
}