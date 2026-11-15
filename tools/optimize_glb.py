# Blender 后台脚本：把资产工作台导出的模型压到网页能用的面数和贴图尺寸。
# Tripo 网页生成固定 12000 面、2K 贴图；监控 320×240、照片 480×360，用不到这么多。
#
# 用法：
#   /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/optimize_glb.py -- \
#       <输入.glb> <输出.glb> <目标三角面数> [贴图最长边，默认 1024]
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, target = argv[0], argv[1], int(argv[2])
tex = int(argv[3]) if len(argv) > 3 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def triangles(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


before = triangles(meshes)
ratio = min(1.0, target / max(before, 1))
if ratio < 1.0:
    for o in meshes:
        mod = o.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
after = triangles(meshes)

for img in bpy.data.images:
    w, h = img.size
    if max(w, h) > tex:
        k = tex / max(w, h)
        img.scale(max(1, round(w * k)), max(1, round(h * k)))
        img.pack()

bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG", export_image_quality=85, export_apply=True)
print(f"OPTIMIZE {src} -> {dst}: {before} -> {after} triangles, textures <= {tex}px")
