/*
 * Copyright LWJGL. All rights reserved.
 * License terms: http://lwjgl.org/license.php
 */
#version 430 core

#define NO_INTERSECTION -1
#define NO_NODE -1
#define EPSILON 1E-5
#define ERROR_COLOR vec3(1.0, 0.0, 1.0)
#define MAX_FOLLOWS 50

layout(binding = 0, rgba8) writeonly uniform image2D framebufferImage;
uniform vec3 eye, ray00, ray01, ray10, ray11;

struct node {
  vec3 min; int left;
  vec3 max; int right;
  int parent, firstVoxel, numVoxels;
};
layout(std430, binding = 0) readonly buffer Nodes {
  node[] nodes;
};

struct voxel {
  ivec3 p;
};
layout(std430, binding = 1) readonly buffer Voxels {
  voxel[] voxels;
};

bool intersectBox(vec3 origin, vec3 invdir, vec3 boxMin, vec3 boxMax, inout float t) {
  bvec3 lt = lessThan(invdir, vec3(0.0));
  vec3 m1 = (boxMin - origin) * invdir;
  vec3 m2 = (boxMax - origin) * invdir;
  vec3 tmin = mix(m1, m2, lt);
  vec3 tmax = mix(m2, m1, lt);
  float mint = max(max(tmin.x, tmin.y), tmin.z);
  float maxt = min(min(tmax.x, tmax.y), tmax.z);
  if (mint < t && maxt >= 0.0 && mint < maxt) {
    t = mint;
    return true;
  } else {
    return false;
  }
}

bool intersectVoxels(vec3 origin, vec3 invdir, const node n, inout float t, out voxel hitvoxel) {
  bool hit = false;
  for (int i = n.firstVoxel; i < n.firstVoxel + n.numVoxels; i++) {
    const voxel v = voxels[i];
    if (intersectBox(origin, invdir, vec3(v.p), vec3(v.p) + vec3(1.0), t)) {
      hit = true;
      hitvoxel = v;
    }
  }
  return hit;
}

vec3 normalForVoxel(vec3 hit, ivec3 v) {
  if (hit.x < float(v.x) + EPSILON)
    return vec3(-1.0, 0.0, 0.0);
  else if (hit.x > float(v.x + 1) - EPSILON)
    return vec3(1.0, 0.0, 0.0);
  else if (hit.y < float(v.y) + EPSILON)
    return vec3(0.0, -1.0, 0.0);
  else if (hit.y > float(v.y + 1) - EPSILON)
    return vec3(0.0, 1.0, 0.0);
  else if (hit.z < float(v.z) + EPSILON)
    return vec3(0.0, 0.0, -1.0);
  else
    return vec3(0.0, 0.0, 1.0);
}

int closestChild(vec3 origin, const node n, out uint leftRight) {
  if (n.left == NO_NODE)
    return NO_NODE;
  const node left = nodes[n.left];
  const node right = nodes[n.right];
  const vec3 midLeft = (left.min + left.max) * vec3(0.5);
  const vec3 midRight = (right.min + right.max) * vec3(0.5);
  const vec3 dl = origin - midLeft;
  const vec3 dr = origin - midRight;
  if (dot(dl, dl) < dot(dr, dr)) {
    leftRight = 0;
    return n.left;
  } else {
    leftRight = 1;
    return n.right;
  }
}

bool processNextFarChild(inout uint nearFarStack, inout uint leftRightStack, inout uint depth, const in node n, inout uint nextIdx) {
  node parent = nodes[n.parent];
  while ((nearFarStack & 1u) == 1u) {
    nearFarStack >>= 1;
    leftRightStack >>= 1;
    depth--;
    if (depth == 0u)
      return false;
    parent = nodes[parent.parent];
  }
  nextIdx = (leftRightStack & 1u) == 0u ? parent.right : parent.left;
  nearFarStack |= 1;
  return true;
}

vec3 trace(vec3 origin, vec3 dir, vec3 invdir) {
  uint nextIdx = 0u;
  float nt = 1.0/0.0, bt = 1.0/0.0;
  vec3 normal = vec3(0.0);
  uint iterations = 0u;
  uint leftRightStack = 0u, nearFarStack = 0u, depth = 0u, leftRight = 0u;
  while (nextIdx != NO_NODE) {
    iterations++;
    if (iterations > MAX_FOLLOWS)
      return ERROR_COLOR;
    const node next = nodes[nextIdx];
    if (!intersectBox(origin, invdir, next.min, next.max, bt)) {
      if (depth == 0u || !processNextFarChild(nearFarStack, leftRightStack, depth, next, nextIdx))
        break;
    } else {
      if (next.numVoxels > 0) {
        voxel hitvoxel;
        if (intersectVoxels(origin, invdir, next, nt, hitvoxel))
          normal = normalForVoxel(origin + nt * dir, hitvoxel.p);
        if (!processNextFarChild(nearFarStack, leftRightStack, depth, next, nextIdx))
          break;
      } else {
        nextIdx = closestChild(origin, next, leftRight);
        nearFarStack <<= 1;
        leftRightStack = leftRightStack << 1 | leftRight;
        depth++;
      }
      bt = nt;
    }
  }
  return vec3(iterations) * 0.02 + normal;
}

layout (local_size_x = 8, local_size_y = 4) in;

void main(void) {
  ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
  ivec2 size = imageSize(framebufferImage);
  if (any(greaterThanEqual(pix, size)))
    return;
  vec2 p = (vec2(pix) + vec2(0.5)) / vec2(size);
  vec3 dir = normalize(mix(mix(ray00, ray01, p.y), mix(ray10, ray11, p.y), p.x));
  vec3 color = trace(eye, dir, 1.0 / dir);
  imageStore(framebufferImage, pix, vec4(color, 1.0));
}
