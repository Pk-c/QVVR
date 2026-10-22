"""Read-only water material/compiled-shader inspection. No asset/bytecode exports."""
import argparse
import ctypes
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".deps/asset-inspection"))
import UnityPy
from UnityPy.enums import ShaderCompilerPlatform
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader
from UnityPy.export.ShaderConverter import ShaderProgram


def disassemble(code):
    code = bytes(code)
    offset = code.find(b"DXBC")
    if offset < 0:
        return ""
    code = code[offset:]
    library = ctypes.WinDLL("d3dcompiler_47.dll")
    function = library.D3DDisassemble
    function.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    function.restype = ctypes.c_long
    blob = ctypes.c_void_p()
    data = ctypes.create_string_buffer(code)
    if function(data, len(code), 0, None, ctypes.byref(blob)) < 0:
        raise RuntimeError("D3D disassembly failed")
    table = ctypes.cast(blob, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    pointer = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(table[3])(blob)
    size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(table[4])(blob)
    result = ctypes.string_at(pointer, size).decode("utf8")
    ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(table[2])(blob)
    return result


def inspect(scene):
    environment = UnityPy.load(str(scene))
    shader = None
    materials = set()
    for obj in list(environment.objects):
        if obj.type.name != "MeshRenderer":
            continue
        renderer = obj.parse_as_object()
        for pointer in renderer.m_Materials:
            if not pointer.m_PathID:
                continue
            material = pointer.deref_parse_as_object()
            if material.m_Name not in ("WaterBlockMat", "InkSpring") or material.m_Name in materials:
                continue
            materials.add(material.m_Name)
            shader = material.m_Shader.deref_parse_as_object()
            properties = material.m_SavedProperties
            print(json.dumps({"material": material.m_Name, "shader": shader.m_ParsedForm.m_Name,
                              "floats": properties.m_Floats,
                              "colors": [(name, str(value)) for name, value in properties.m_Colors]}, default=str))
    if shader is None:
        return
    print("SHADER PROPERTIES", [(p.m_Name, p.m_Description) for p in shader.m_ParsedForm.m_PropInfo.m_Props])
    print("SHADER FALLBACK", shader.m_ParsedForm.m_FallbackName)
    print("SHADER TAGS", [str(sub.m_Tags) for sub in shader.m_ParsedForm.m_SubShaders])
    selected = set()
    for sub in shader.m_ParsedForm.m_SubShaders:
        for shader_pass in sub.m_Passes[:1]:
            names = {value: name for name, value in shader_pass.m_NameIndices}
            for stage_name in ("progVertex", "progFragment"):
                stage = getattr(shader_pass, stage_name)
                for program in stage.m_SubPrograms[:1]:
                    params = program.m_Parameters or program
                    print("PARAMETERS", stage_name, "blob", program.m_BlobIndex)
                    selected.add(program.m_BlobIndex)
                    for buffer in params.m_ConstantBuffers or []:
                        print("BUFFER", names.get(buffer.m_NameIndex), "SIZE", buffer.m_Size,
                              "vectors", [(names.get(v.m_NameIndex), v.m_Index) for v in buffer.m_VectorParams or []],
                              "matrices", [(names.get(v.m_NameIndex), v.m_Index) for v in buffer.m_MatrixParams or []])
    for index, platform in enumerate(shader.platforms):
        if platform != ShaderCompilerPlatform.kShaderCompPlatformD3D11:
            continue
        def entry(values):
            value = values[index]
            return value[0] if isinstance(value, list) else value
        offset, compressed, size = entry(shader.offsets), entry(shader.compressedLengths), entry(shader.decompressedLengths)
        raw = CompressionHelper.decompress_lz4(bytes(shader.compressedBlob)[offset:offset + compressed], size)
        programs = ShaderProgram(EndianBinaryReader(raw, endian="<"), shader.object_reader.version)
        for number in sorted(selected):
            program = programs.m_SubPrograms[number]
            print("DISASSEMBLY", number, "TYPE", program.m_ProgramType, "KEYWORDS", program.m_Keywords)
            print(disassemble(program.m_ProgramCode))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scene", type=Path)
    inspect(parser.parse_args().scene)
