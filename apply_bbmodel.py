#!/usr/bin/env python3
"""Adds Blockbench (.bbmodel) support to the Luanti fork.
Run from the repository root:  python3 apply_bbmodel.py
Safe to run repeatedly: already applied edits are skipped. Nothing is written
unless every edit can be applied."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.getcwd()

def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8", newline="") as f:
        return f.read()

EDITS = []  # (file, marker_if_applied, old, new)

def edit(path, marker, old, new):
    EDITS.append((path, marker, old, new))

# --- SkinnedMesh.h
edit("irr/include/SkinnedMesh.h", "BBMODEL,",
     "\t\tGLTF,\n\t\tOTHER,",
     "\t\tGLTF,\n\t\tBBMODEL,\n\t\tOTHER,")
edit("irr/include/SkinnedMesh.h", "getEmbeddedTexture(u32 slot)",
     "\tf32 getMaxFrameNumber(u16 track_nr) const override;\n",
     "\tf32 getMaxFrameNumber(u16 track_nr) const override;\n\n"
     "\t//! Raw file contents (e.g. PNG) of an image embedded in the model file\n"
     "\t//! for the given texture slot, or nullptr if the model has none.\n"
     "\tconst std::string *getEmbeddedTexture(u32 slot) const\n\t{\n"
     "\t\tif (slot >= EmbeddedTextures.size() || EmbeddedTextures[slot].empty())\n"
     "\t\t\treturn nullptr;\n\t\treturn &EmbeddedTextures[slot];\n\t}\n")
edit("irr/include/SkinnedMesh.h", "std::vector<std::string> EmbeddedTextures;",
     "\t//! Mapping from meshbuffer number to bindable texture slot\n\tstd::vector<u32> TextureSlots;\n",
     "\t//! Mapping from meshbuffer number to bindable texture slot\n\tstd::vector<u32> TextureSlots;\n\n"
     "\t//! Images embedded in the model file, indexed by texture slot (may be empty strings)\n"
     "\tstd::vector<std::string> EmbeddedTextures;\n")
edit("irr/include/SkinnedMesh.h", "void setEmbeddedTexture(",
     "\t\tmesh->TextureSlots.at(meshbufNr) = textureSlot;\n\t}\n",
     "\t\tmesh->TextureSlots.at(meshbufNr) = textureSlot;\n\t}\n\n"
     "\t//! Attaches raw image file contents (e.g. PNG) to a texture slot\n"
     "\tvoid setEmbeddedTexture(u32 slot, std::string data)\n\t{\n"
     "\t\tif (mesh->EmbeddedTextures.size() <= slot)\n"
     "\t\t\tmesh->EmbeddedTextures.resize(slot + 1);\n"
     "\t\tmesh->EmbeddedTextures[slot] = std::move(data);\n\t}\n")
# --- scene manager + cmake
edit("irr/src/CSceneManager.cpp", '#include "CBBMeshFileLoader.h"',
     '#include "CB3DMeshFileLoader.h"\n',
     '#include "CB3DMeshFileLoader.h"\n#include "CBBMeshFileLoader.h"\n')
edit("irr/src/CSceneManager.cpp", "new CBBMeshFileLoader()",
     "\tMeshLoaderList.push_back(new CGLTFMeshFileLoader());\n",
     "\tMeshLoaderList.push_back(new CGLTFMeshFileLoader());\n\tMeshLoaderList.push_back(new CBBMeshFileLoader());\n")
edit("irr/src/CMakeLists.txt", "CBBMeshFileLoader.h",
     "\tCB3DMeshFileLoader.h\n", "\tCB3DMeshFileLoader.h\n\tCBBMeshFileLoader.h\n")
edit("irr/src/CMakeLists.txt", "CBBMeshFileLoader.cpp",
     "\tCB3DMeshFileLoader.cpp\n", "\tCB3DMeshFileLoader.cpp\n\tCBBMeshFileLoader.cpp\n")
# --- nodes: bbmodel scaled like glTF
edit("src/client/node_visuals.cpp", "SourceFormat::BBMODEL",
     "\t\t\tbool is_gltf = skinned_mesh->getSourceFormat() ==\n\t\t\t\t\tscene::SkinnedMesh::SourceFormat::GLTF;\n",
     "\t\t\tconst auto src_format = skinned_mesh->getSourceFormat();\n"
     "\t\t\tbool is_gltf = src_format == scene::SkinnedMesh::SourceFormat::GLTF ||\n"
     "\t\t\t\t\tsrc_format == scene::SkinnedMesh::SourceFormat::BBMODEL;\n")
# --- entities: fall back to the embedded texture
edit("src/client/content_cao.cpp", "getEmbeddedTexture(m_prop.mesh",
     "\t\t\t\tif (texture_idx >= m_prop.textures.size())\n\t\t\t\t\tcontinue;\n"
     "\t\t\t\tstd::string texturestring = m_prop.textures[texture_idx];\n",
     "\t\t\t\tstd::string texturestring;\n"
     "\t\t\t\tif (texture_idx < m_prop.textures.size())\n"
     "\t\t\t\t\ttexturestring = m_prop.textures[texture_idx];\n"
     "\t\t\t\tif (texturestring.empty()) {\n"
     "\t\t\t\t\t// Fall back to a texture embedded in the model file (.bbmodel)\n"
     "\t\t\t\t\ttexturestring = m_client->getEmbeddedTexture(m_prop.mesh,\n"
     "\t\t\t\t\t\t\tm_animated_meshnode->getMesh(), texture_idx);\n"
     "\t\t\t\t}\n")
# --- client
edit("src/client/client.h", "std::string getEmbeddedTexture(",
     "\tvirtual scene::IAnimatedMesh* getMesh(const std::string &filename, bool cache = false);\n",
     "\tvirtual scene::IAnimatedMesh* getMesh(const std::string &filename, bool cache = false);\n"
     "\t/**\n\t * Registers the image embedded in a model file (e.g. .bbmodel) for the given\n"
     "\t * texture slot as a texture and returns its name.\n"
     "\t * @return texture name, or empty string if the mesh has no embedded texture for that slot\n\t */\n"
     "\tstd::string getEmbeddedTexture(const std::string &mesh_name,\n"
     "\t\t\tconst scene::IAnimatedMesh *mesh, u32 slot);\n")
edit("src/client/client.h", "m_embedded_textures;",
     "\tStringMap m_mesh_data;\n",
     "\tStringMap m_mesh_data;\n\t// Names of textures registered from images embedded in model files\n"
     "\tstd::unordered_set<std::string> m_embedded_textures;\n")
edit("src/client/client.cpp", '#include "SkinnedMesh.h"',
     '#include "client.h"\n', '#include "client.h"\n#include "SkinnedMesh.h"\n')
edit("src/client/client.cpp", '".glb", ".bbmodel"',
     '".x", ".b3d", ".obj", ".gltf", ".glb",\n', '".x", ".b3d", ".obj", ".gltf", ".glb", ".bbmodel",\n')
edit("src/client/client.cpp", "Client::getEmbeddedTexture(",
     "\n/*\n * Mod channels\n */\n",
     "\nstd::string Client::getEmbeddedTexture(const std::string &mesh_name,\n"
     "\t\tconst scene::IAnimatedMesh *mesh, u32 slot)\n{\n"
     "\tconst auto *skinned = dynamic_cast<const scene::SkinnedMesh *>(mesh);\n"
     "\tif (!skinned)\n\t\treturn \"\";\n"
     "\tconst std::string *data = skinned->getEmbeddedTexture(slot);\n"
     "\tif (!data)\n\t\treturn \"\";\n\n"
     "\tconst std::string name = \"_embedded_\" + mesh_name + \"_\" + itos(slot) + \".png\";\n"
     "\tif (m_embedded_textures.count(name))\n\t\treturn name;\n\n"
     "\tio::IReadFile *rfile = m_rendering_engine->get_filesystem()->createMemoryReadFile(\n"
     "\t\t\tdata->c_str(), data->size(), name.c_str());\n"
     "\tif (!rfile)\n\t\treturn \"\";\n"
     "\tvideo::IImage *img = m_rendering_engine->get_video_driver()->createImageFromFile(rfile);\n"
     "\trfile->drop();\n"
     "\tif (!img) {\n"
     "\t\twarningstream << \"Client: Cannot decode texture \" << slot\n"
     "\t\t\t\t<< \" embedded in \\\"\" << mesh_name << \"\\\"\" << std::endl;\n"
     "\t\treturn \"\";\n\t}\n"
     "\tm_tsrc->insertSourceImage(name, img);\n\timg->drop();\n"
     "\tm_embedded_textures.insert(name);\n\treturn name;\n}\n\n/*\n * Mod channels\n */\n")
# --- server media extensions
edit("src/server.cpp", '".glb", ".bbmodel"',
     '".x", ".b3d", ".obj", ".gltf", ".glb",\n', '".x", ".b3d", ".obj", ".gltf", ".glb", ".bbmodel",\n')
# --- docs (best effort)
DOC_OLD = "The .x, .b3d and .gltf formats additionally support (a single) animation.\n"
doc_new = open(os.path.join(HERE, "bbmodel_doc.md"), encoding="utf-8").read()

def main():
    ok = True
    plan = {}
    for path, marker, old, new in EDITS:
        if not os.path.exists(os.path.join(ROOT, path)):
            print("MISSING FILE:", path); ok = False; continue
        text = plan.get(path, read(path))
        if marker in text:
            continue
        n = text.count(old)
        if n != 1:
            print("CANNOT APPLY (found %d times) in %s:\n  %r" % (n, path, old[:70])); ok = False; continue
        plan[path] = text.replace(old, new, 1)
    for f in ("CBBMeshFileLoader.cpp", "CBBMeshFileLoader.h"):
        if not os.path.exists(os.path.join(HERE, "irr", "src", f)):
            print("loader file missing next to the script:", f); ok = False
    if not ok:
        print("\nNothing was changed."); sys.exit(1)
    for path, text in plan.items():
        with open(os.path.join(ROOT, path), "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print("edited", path)
    for f in ("CBBMeshFileLoader.cpp", "CBBMeshFileLoader.h"):
        data = open(os.path.join(HERE, "irr", "src", f), "rb").read()
        dst = os.path.join(ROOT, "irr", "src", f)
        if not os.path.exists(dst) or open(dst, "rb").read() != data:
            open(dst, "wb").write(data); print("wrote irr/src/" + f)
    # docs
    try:
        d = read("doc/lua_api.md")
        if "Blockbench" not in d and d.count(DOC_OLD) == 1:
            d = d.replace(DOC_OLD, doc_new.rstrip("\n") + "\n", 1)
            d = d.replace("(since version 5.10:) .gltf, .glb\n", "(since version 5.10:) .gltf, .glb, .bbmodel\n", 1)
            with open(os.path.join(ROOT, "doc/lua_api.md"), "w", encoding="utf-8", newline="") as f:
                f.write(d)
            print("edited doc/lua_api.md")
    except Exception as e:
        print("docs skipped:", e)
    print("\nDone. .bbmodel support added.")

main()
