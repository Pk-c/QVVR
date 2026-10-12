"""Read-only liquid shader metadata inspection; never exports game bytecode/assets.

Dev-only dependency: UnityPy==1.25.0 under ignored .deps/asset-inspection.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".deps/asset-inspection"))
import UnityPy


def inspect(scene):
    env = UnityPy.load(str(scene))
    seen = set()
    for obj in list(env.objects):
        if obj.type.name not in ("MeshRenderer", "SkinnedMeshRenderer"):
            continue
        renderer = obj.parse_as_object()
        go = renderer.m_GameObject.deref_parse_as_object()
        for pointer in renderer.m_Materials:
            if not pointer.m_PathID:
                continue
            material = pointer.deref_parse_as_object()
            shader = material.m_Shader.deref_parse_as_object()
            parsed = shader.m_ParsedForm
            if not any(word in (go.m_Name + material.m_Name + parsed.m_Name).lower()
                       for word in ("water", "paint", "liquid", "pot")):
                continue
            key = (go.m_Name, material.m_Name, parsed.m_Name)
            if key in seen:
                continue
            seen.add(key)
            passes = []
            for sub in parsed.m_SubShaders:
                for shader_pass in sub.m_Passes:
                    names = set()
                    indices = {index: name for name, index in shader_pass.m_NameIndices}
                    for program in (shader_pass.progVertex, shader_pass.progFragment):
                        for part in program.m_SubPrograms:
                            params = part.m_Parameters or part
                            for field in ("m_VectorParams", "m_MatrixParams", "m_TextureParams"):
                                names.update(indices.get(p.m_NameIndex, "") for p in (getattr(params, field, None) or []))
                            for buffer in (getattr(params, "m_ConstantBuffers", None) or []):
                                for field in ("m_VectorParams", "m_MatrixParams"):
                                    names.update(indices.get(p.m_NameIndex, "") for p in (getattr(buffer, field, None) or []))
                    passes.append({"name": shader_pass.m_Name, "type": shader_pass.m_Type,
                                   "zwrite": shader_pass.m_State.zWrite.val,
                                   "cull": shader_pass.m_State.culling.val,
                                   "blend": [shader_pass.m_State.rtBlend0.srcBlend.val,
                                             shader_pass.m_State.rtBlend0.destBlend.val,
                                             shader_pass.m_State.rtBlend0.colMask.val],
                                   "camera_inputs": sorted(n for n in names if any(
                                       w in n.lower() for w in ("camera", "depth", "grab", "view", "screen", "projection", "ortho")))})
            print(json.dumps({"scene": scene.name, "object": go.m_Name, "material": material.m_Name,
                              "shader": parsed.m_Name, "queue": material.m_CustomRenderQueue,
                              "passes": passes}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenes", nargs="+", type=Path)
    for scene in parser.parse_args().scenes:
        inspect(scene)
