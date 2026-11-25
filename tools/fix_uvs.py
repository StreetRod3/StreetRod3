import argparse
import io
import sys
import numpy as np
import trimesh


def apply_planar_box_uvs(
    mesh: trimesh.Trimesh, scale: float
) -> trimesh.Trimesh:
  mesh.unmerge_vertices()

  vertices = mesh.vertices
  face_normals = mesh.face_normals

  vertex_normals = np.repeat(face_normals, 3, axis=0)
  abs_n = np.abs(vertex_normals)

  uvs = np.zeros((len(vertices), 2), dtype=np.float32)

  is_x_dominant = (abs_n[:, 0] >= abs_n[:, 1]) & (abs_n[:, 0] >= abs_n[:, 2])
  is_z_dominant = (~is_x_dominant) & (abs_n[:, 2] >= abs_n[:, 1])
  is_y_dominant = (~is_x_dominant) & (~is_z_dominant)

  # Side panels (X-facing) -> project onto Z and Y
  uvs[is_x_dominant, 0] = vertices[is_x_dominant, 2] * scale
  uvs[is_x_dominant, 1] = vertices[is_x_dominant, 1] * scale

  # Front/Back panels (Z-facing) -> project onto X and Y
  uvs[is_z_dominant, 0] = vertices[is_z_dominant, 0] * scale
  uvs[is_z_dominant, 1] = vertices[is_z_dominant, 1] * scale

  # Top/Bottom panels (Y-facing) -> project onto X and Z
  uvs[is_y_dominant, 0] = vertices[is_y_dominant, 0] * scale
  uvs[is_y_dominant, 1] = vertices[is_y_dominant, 2] * scale

  if hasattr(mesh.visual, "material"):
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=uvs, material=mesh.visual.material
    )
  else:
    mesh.visual.uv = uvs

  return mesh


def main():
  parser = argparse.ArgumentParser(
      description="Rewrite GLB UVs via files or stdin/stdout."
  )
  parser.add_argument(
      "-i",
      "--input",
      type=argparse.FileType("rb"),
      default=sys.stdin.buffer,
      help="Input .glb file path (defaults to stdin)",
  )
  parser.add_argument(
      "-o",
      "--output",
      type=argparse.FileType("wb"),
      default=sys.stdout.buffer,
      help="Output .glb file path (defaults to stdout)",
  )
  parser.add_argument(
      "-s",
      "--scale",
      type=float,
      default=0.5,
      help="Texel scale factor (default: 0.5)",
  )
  parser.add_argument(
      "-m",
      "--mesh",
      type=str,
      default=None,
      help="Specific mesh name to target (optional)",
  )
  args = parser.parse_args()

  input_bytes = args.input.read()
  if not input_bytes:
    sys.stderr.write("Error: No input data received.\n")
    sys.exit(1)

  scene = trimesh.load(io.BytesIO(input_bytes), file_type="glb", force="scene")

  for name, geom in scene.geometry.items():
    if isinstance(geom, trimesh.Trimesh):
      if args.mesh is None or name == args.mesh:
        sys.stderr.write(f"Re-projecting UVs for: {name}\n")
        scene.geometry[name] = apply_planar_box_uvs(geom, args.scale)

  output_bytes = scene.export(file_type="glb")
  args.output.write(output_bytes)
  args.output.flush()


if __name__ == "__main__":
  main()
