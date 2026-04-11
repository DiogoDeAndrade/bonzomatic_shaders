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
#define MAX_ITER_SHADOW 200
#define SHADOW_STEP 0.2

cbuffer constants
{
	float fGlobalTime;    // in seconds
	float2 v2Resolution;  // viewport resolution (in pixels)
	float fFrameTime;     // duration of the last frame, in seconds
}

struct Light
{
  float3 pos;
  float3 color;
  float intensity;
  float size;
};

struct SceneData
{
  Light   mainLight;
  float3  ambientLight;
};

struct Material
{
  int    type;
  float4 color;
  float4 emission;
};

Material make_material(float4 color, int type = 0, float4 emission = float4(0,0,0,0))
{
    Material m;
    m.type = type;
    m.color = color;
    m.emission = emission;
    return m;
}

float4 checkboard_pattern(float3 pos)
{
  int3 ip = floor(pos * 0.25);
  
  if (((ip.x + ip.z) % 2) == 0)
    return float4(0.2,1,1,1);
  else
    return float4(0.2,0.2,1,1);
}

float4 material_get_emission(float3 pos, Material mat)
{
  if (mat.type == 0) 
    return mat.emission;
  else
    return mat.emission * checkboard_pattern(pos);
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

#define MATERIAL_RED    make_material(float4(1, 0.2, 0.2, 1))
#define MATERIAL_GREEN  make_material(float4(0.2, 1, 0.2, 1))

float4 plas( float2 v, float time)
{
	float c = 0.5 + sin( v.x * 10.0 ) + cos( sin( time + v.y ) * 20.0 );
	return float4(sin(c * 0.2 + cos(time)), c * 0.15, cos( c * 0.1 + time / .4 ) * .25, 1.0 );
}

float hash(float3 p)
{
  return frac(sin(dot(p, float3(12.9898, 78.233, 37.719))) * 43758.5453);
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

float3 transform_translate(float3 p, float3 offset)
{
  return p - offset;
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

SdfResult scene(SceneData data, float3 p, bool renderLights = false)
{
  float3 p1 = transform_rotateY(p, fGlobalTime);
  
  SdfResult sceneRes = 
    op_union(
      op_subtraction(
        sd_box(p1, float3(3,3,3), MATERIAL_RED),
        sd_sphere(p1, 4, MATERIAL_RED)
      ),
      sd_plane(p1, float3(0, 1, 0), 3, make_material(float4(1, 1, 0, 1), 1))
    );
  
  if (renderLights)
  {
    float3 pLight = transform_translate(p, data.mainLight.pos);
    sceneRes = op_union(sceneRes,
                        sd_sphere(pLight, data.mainLight.size, make_material(float4(data.mainLight.color, 1), 0, float4(data.mainLight.color, 1))));
  }
  return sceneRes;
}

float3 compute_normal(SceneData sceneData, SdfResult r, float3 p)
{
  float eps = 0.001;
  float dx = scene(sceneData, p + float3(eps, 0, 0)).dist - r.dist;
  float dy = scene(sceneData, p + float3(0, eps, 0)).dist - r.dist;
  float dz = scene(sceneData, p + float3(0, 0, eps)).dist - r.dist;
  
  float3 n = float3(dx, dy, dz);
  
  return normalize(n);
}

float raymarch_to_light(SceneData sceneData, float3 pos, float3 dir, float maxDist)
{
    float t = 0.05;
    float shadow = 1.0;

    for (int i = 0; i < MAX_ITER_SHADOW; i++)
    {
        float3 currentPos = pos + dir * t;
        // Eventually experiment with jittering this point, it might lead to interesting results
        SdfResult current = scene(sceneData, currentPos);

        if (current.dist < 1e-3)
        {
            return 0.0;
        }

        // Soft shadow heuristic:
        // larger value = more lit, smaller = more occluded
        float k = 16.0 / sceneData.mainLight.size;
        shadow = min(shadow, k * current.dist / t);

        t += current.dist * SHADOW_STEP;

        if (t >= maxDist)
            break;
    }

    return saturate(shadow);
}

#define AO_HEMISPHERE_SAMPLES 32
#define AO_HEMISPHERE_RANGE 1
#define AO_HEMISPHERE_BIAS 0.1

float4 compute_ao_sampled(SceneData sceneData, float3 pos, float3 normal)
{
  float accum = 0.0f;
  float3 offset;
  
  // Build TBN basis - only needed with cosine-weighted directions
  float3 up = (abs(normal.y) < 0.999) ? float3(0,1,0) : float3(1,0,0);
  float3 tangent = cross(up, normal);
  float3 bitangent = cross(tangent, normal);
  
  // Offset origin
  float3 origin = pos + normal * 0.01;
  
  for (int i = 0; i < AO_HEMISPHERE_SAMPLES; i++)
  {
    // This code is to generate hemisphere samples with rejection sampling
    /*offset.x = hash(pos + ((i + 1) * 0.1) * float3(pos.y, pos.z, pos.x)) * 2 - 1;
    offset.y = hash(pos + ((i + 1) * 0.1) * float3(pos.z, pos.x, pos.y)) * 2 - 1;
    offset.z = hash(pos + ((i + 1) * 0.1) * float3(pos.x, pos.y, pos.z)) * 2 - 1;
    offset = normalize(offset);
    
    if (dot(offset, normal) < 0) offset = -offset;//*/    
    
    // This code generates cosine-weighted directions (hard to remember, this is why I implement hemisphere points with rejection sampling)
    float u1 = hash(pos + ((i + 1) * 0.1) * float3(pos.y, pos.z, pos.x));
    float u2 = hash(pos + ((i + 1) * 0.1) * float3(pos.z, pos.x, pos.y));
    
    float rr = sqrt(u1);
    float phi = 2 * PI * u2;
    
    float3 localDir;
    localDir.x = rr * cos(phi);
    localDir.y = rr * sin(phi);
    localDir.z = sqrt(1 - u1);
    
    float3 offset = localDir.x * tangent + localDir.y * bitangent + localDir.z * normal;//*/

    float   d = 0.02 + 0.98 * hash(pos + ((i + 1) * 0.1) * float3(pos.x * pos.y, pos.y * pos.z, pos.z * pos.x));
    d *= AO_HEMISPHERE_RANGE;
    float3  newPos = origin + offset * d;
    
    SdfResult rScene = scene(sceneData, newPos);
    // Binary test
    //if (rScene.dist > 0) accum += 1.0;
    // Continuous test - more noisy, more character
    accum += saturate((rScene.dist + AO_HEMISPHERE_BIAS) / d);
  }
  return float4(1,1,1,1) * accum / AO_HEMISPHERE_SAMPLES;
}

#define AO_NORMAL_SAMPLES 4
#define AO_NORMAL_RANGE   1

float compute_ao_normal(SceneData sceneData, float3 pos, float3 normal)
{
    float occlusion = 0.0;
    float weight = 1.0;
    float step = (float)AO_NORMAL_RANGE / AO_NORMAL_SAMPLES;

    for (int i = 1; i <= AO_NORMAL_SAMPLES; i++)
    {
        float t = i * step;
        float d = scene(sceneData, pos + normal * t).dist;

        // If d < t, nearby geometry is constraining the field
        occlusion += weight * max(0.0, t - d);

        // Near samples matter more
        weight *= 0.5;
    }

    return saturate(1.0 - occlusion);
}

float4 compute_lighting(SceneData sceneData, float3 pos, float3 normal, SdfResult r)
{
  pos += normal * 0.01;
  
  float  distanceToLight = length(sceneData.mainLight.pos - pos);
  float3 toLight = normalize(sceneData.mainLight.pos - pos);
  float dt = max(0, dot(toLight, normal));
  float atten = sceneData.mainLight.intensity / (1 + distanceToLight * distanceToLight);
  
  // Shadowcast
  float   shadow = raymarch_to_light(sceneData, pos, toLight, distanceToLight);
  //float3  ambientLight = sceneData.ambientLight * compute_ao_sampled(sceneData, pos, normal);
  float3  ambientLight = sceneData.ambientLight * compute_ao_normal(sceneData, pos, normal);
  float3  diffuseLighting = atten * shadow * dt * sceneData.mainLight.color;
  float3  emission = material_get_emission(pos, r.mat).rgb;
  
  return float4((ambientLight + diffuseLighting) * material_get_color(pos, r.mat).rgb + emission, 1);
}

float4 main( float4 position : SV_POSITION, float2 TexCoord : TEXCOORD ) : SV_TARGET
{
  float aspect = v2Resolution.x / v2Resolution.y;

  float2 uv = TexCoord * 2 - 1;
  uv.x *= aspect;
  
	float4 col = 0;
  
  float fovY = PI / 4;
  float t = tan(fovY * 0.5);
  float3 currentPos = float3(0, 4, -30);
  float3 currentDir = normalize(float3(uv.x * t, uv.y * t, 1));
 
  SceneData sceneData;
  //sceneData.mainLight.pos = float3(5 * sin(fGlobalTime), 5, 0);
  sceneData.mainLight.pos = float3(9, 10, 0);
  sceneData.mainLight.color = float3(1.0, 1.0, 1.0);
  sceneData.mainLight.size = 1;
  sceneData.mainLight.intensity = 100.0;
  sceneData.ambientLight = float3(0.1, 0.1, 0.1);
  
  for (int i = 0; i < MAX_ITER; i++)
  {
    SdfResult current = scene(sceneData, currentPos, true);
    if (current.dist < 1e-3)
    {
      // Got inside
      float3 normal = compute_normal(sceneData, current, currentPos);
      //col = float4(normal.xyz * 0.5 + 0.5, 1);
      //col = current.mat.color;
     
      col = compute_lighting(sceneData, currentPos, normal, current);

      break;
    }
    else
    {
      currentPos += currentDir * max(current.dist * 0.9, 0.01);
    }
  }
  
  if (i == MAX_ITER) col = plas(uv * 0.1, 0.1 * fGlobalTime);
 
  // Exposure control
  float exposure = 3;
  col.rgb = 1 - exp(-col.rgb * exposure);
  
	return col;
}