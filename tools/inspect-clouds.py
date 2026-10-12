"""Read-only Unity scene metadata inspection. Never patches/exports game assets.

Dev-only dependency: UnityPy==1.25.0 in .deps/asset-inspection (not packaged).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".deps/asset-inspection"))
import UnityPy

cache = {}


def read(pointer):
    key = (id(pointer.assetsfile), pointer.m_FileID, pointer.m_PathID)
    if key not in cache:
        cache[key] = pointer.deref_parse_as_object()
    return cache[key]


def hierarchy(game_object):
    names = [game_object.m_Name]
    for component in game_object.m_Component:
        obj = component.component.deref()
        if obj.type.name not in ("Transform", "RectTransform"):
            continue
        transform = read(component.component)
        seen = set()
        while transform.m_Father.m_PathID and transform.m_Father.m_PathID not in seen:
            seen.add(transform.m_Father.m_PathID)
            transform = read(transform.m_Father)
            names.insert(0, read(transform.m_GameObject).m_Name)
        break
    return "/".join(names)


def inspect(scene):
    env = UnityPy.load(str(scene))
    # External material/shader pointers can lazily load additional files.
    # Keep the inspected scene's object inventory fixed and cache parsed metadata.
    cache.clear()
    for obj in list(env.objects):
        if obj.type.name not in ("MeshRenderer", "SkinnedMeshRenderer", "ParticleSystemRenderer"):
            continue
        renderer = obj.parse_as_object()
        go = read(renderer.m_GameObject)
        path = hierarchy(go)
        materials = []
        for pointer in renderer.m_Materials:
            if not pointer.m_PathID:
                continue
            material = read(pointer)
            shader = read(material.m_Shader)
            shader_name = getattr(shader, "m_Name", "") or getattr(getattr(shader, "m_ParsedForm", None), "m_Name", "")
            materials.append({"material": material.m_Name, "shader": shader_name})
        if "cloud" not in path.lower() and not any("cloud" in str(m).lower() for m in materials):
            continue
        print(json.dumps({"scene": scene.name, "path": path, "renderer": obj.type.name,
                          "layer": go.m_Layer, "materials": materials}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenes", nargs="+", type=Path)
    args = parser.parse_args()
    for scene in args.scenes:
        inspect(scene)
