#!/usr/bin/env python3
"""Adds Blockbench (.bbmodel) support to the repo with small anchored edits.
Never overwrites whole files, so it is safe on the newest code. Safe to run twice.
Usage: python3 apply_bbmodel.py   (from the repo root)"""
import sys, os
FN = 'std::string Client::getEmbeddedTexture(const std::string &mesh_name,\n\t\tconst scene::IAnimatedMesh *mesh, u32 slot)\n{\n\tconst auto *skinned = dynamic_cast<const scene::SkinnedMesh *>(mesh);\n\tif (!skinned)\n\t\treturn "";\n\tconst std::string *data = skinned->getEmbeddedTexture(slot);\n\tif (!data)\n\t\treturn "";\n\n\tconst std::string name = "_embedded_" + mesh_name + "_" + itos(slot) + ".png";\n\tif (m_embedded_textures.count(name))\n\t\treturn name;\n\n\tio::IReadFile *rfile = m_rendering_engine->get_filesystem()->createMemoryReadFile(\n\t\t\tdata->c_str(), data->size(), name.c_str());\n\tif (!rfile)\n\t\treturn "";\n\tvideo::IImage *img = m_rendering_engine->get_video_driver()->createImageFromFile(rfile);\n\trfile->drop();\n\tif (!img) {\n\t\twarningstream << "Client: Cannot decode texture " << slot\n\t\t\t\t<< " embedded in \\"" << mesh_name << "\\"" << std::endl;\n\t\treturn "";\n\t}\n\tm_tsrc->insertSourceImage(name, img);\n\timg->drop();\n\tm_embedded_textures.insert(name);\n\treturn name;\n}\n'
DOC = '#### Blockbench (`.bbmodel`)\n\nModels saved by [Blockbench](https://www.blockbench.net/) can be used directly,\nwithout exporting them first: `mesh = "model.bbmodel"`.\n\n* Geometry: cubes (box UV and per-face UV, rotation, inflate, mirrored UV)\n  and mesh elements.\n* Groups are bones. Their names are the bone names for bone overrides.\n  Cubes are attached rigidly to their group; there are no skin weights.\n* Animations are loaded by name, exactly as named in Blockbench\n  (e.g. `walk`, `idle`). Use `play_animation("walk", {loop = false})`.\n  Rotation, position and scale keyframes are supported. Keyframe times are in\n  seconds, so use a speed of `1.0`. The loop mode set in Blockbench is not\n  used; pass `loop` explicitly.\n  `catmullrom` and `bezier` keyframes are played back as `linear`, and `step`\n  keyframes are respected. Molang expressions are not supported.\n  Rotation keyframes are interpolated as quaternions, not as Euler angles.\n* Textures: a texture embedded in the model (the default when saving from\n  Blockbench) is used automatically for every texture slot for which the\n  `textures` property (or `tiles`, ...) of the object does not supply\n  one. A texture you supply yourself takes precedence. The texture slot of a\n  face is the index of its texture in Blockbench. Embedded textures are\n  currently used for entities only.\n* Scale: 16 Blockbench pixels = 1 node = 10 units. The front of a Blockbench\n  model (its north side) is the front of the Luanti model.\n* Not supported: Bedrock/Java-specific axis conventions, texture animation\n  frames, locators and other non-geometry elements.'
bad = 0
def edit(path, old, new, after=False, marker=None):
    global bad
    if not os.path.exists(path):
        print("MISSING FILE", path); bad += 1; return
    s = open(path, encoding="utf-8").read()
    if (marker or new) in s:
        print("ok (already)", path); return
    if s.count(old) != 1:
        print("ANCHOR NOT FOUND (%d)" % s.count(old), path, repr(old[:60])); bad += 1; return
    s = s.replace(old, old + new if after else new)
    open(path, "w", encoding="utf-8").write(s)
    print("edited", path)
for p in ("src/server.cpp", "src/client/client.cpp"):
    s = open(p, encoding="utf-8").read()
    if ".bbmodel" in s: print("ok (already)", p, "ext")
    elif s.count('".gltf", ".glb",') != 1: print("ANCHOR NOT FOUND ext", p); bad += 1
    else: open(p, "w", encoding="utf-8").write(s.replace('".gltf", ".glb",', '".gltf", ".glb", ".bbmodel",')); print("edited", p, "ext")
edit("src/client/client.cpp", '#include "client.h"\n', '#include "SkinnedMesh.h"\n', after=True)
edit("src/client/client.cpp", "scene::IAnimatedMesh* Client::getMesh(const std::string &filename, bool cache)",
     FN + "\n" + "scene::IAnimatedMesh* Client::getMesh(const std::string &filename, bool cache)", marker="Client::getEmbeddedTexture")
edit("src/client/client.h", "\tvirtual scene::IAnimatedMesh* getMesh(const std::string &filename, bool cache = false);\n",
 "\tstd::string getEmbeddedTexture(const std::string &mesh_name,\n\t\t\tconst scene::IAnimatedMesh *mesh, u32 slot);\n", after=True, marker="getEmbeddedTexture")
edit("src/client/client.h", "\tstd::unordered_set<std::string> m_privileges;\n",
 "\t// Names of textures registered from images embedded in model files\n\tstd::unordered_set<std::string> m_embedded_textures;\n", after=True, marker="m_embedded_textures")
edit("irr/src/CMakeLists.txt", "\tCB3DMeshFileLoader.h\n", "\tCBBMeshFileLoader.h\n", after=True)
edit("irr/src/CMakeLists.txt", "\tCB3DMeshFileLoader.cpp\n", "\tCBBMeshFileLoader.cpp\n", after=True)
edit("irr/src/CSceneManager.cpp", '#include "CB3DMeshFileLoader.h"\n', '#include "CBBMeshFileLoader.h"\n', after=True)
edit("irr/src/CSceneManager.cpp", "\tMeshLoaderList.push_back(new CGLTFMeshFileLoader());\n", "\tMeshLoaderList.push_back(new CBBMeshFileLoader());\n", after=True)
edit("irr/include/SkinnedMesh.h", "\t\tGLTF,\n", "\t\tBBMODEL,\n", after=True)
edit("irr/include/SkinnedMesh.h", "\tvoid prepareForAnimation(u16 max_hw_joints) override;\n",
 "\t//! Raw file contents (e.g. PNG) of an image embedded in the model file\n\t//! for the given texture slot, or nullptr if the model has none.\n\tconst std::string *getEmbeddedTexture(u32 slot) const\n\t{\n\t\tif (slot >= EmbeddedTextures.size() || EmbeddedTextures[slot].empty())\n\t\t\treturn nullptr;\n\t\treturn &EmbeddedTextures[slot];\n\t}\n\n\tvoid prepareForAnimation(u16 max_hw_joints) override;\n", marker="getEmbeddedTexture")
edit("irr/include/SkinnedMesh.h", "\tstd::vector<u32> TextureSlots;\n",
 "\n\t//! Images embedded in the model file, indexed by texture slot (may be empty strings)\n\tstd::vector<std::string> EmbeddedTextures;\n", after=True, marker="EmbeddedTextures;")
edit("irr/include/SkinnedMesh.h", "\t\tmesh->TextureSlots.at(meshbufNr) = textureSlot;\n\t}\n",
 "\n\t//! Attaches raw image file contents (e.g. PNG) to a texture slot\n\tvoid setEmbeddedTexture(u32 slot, std::string data)\n\t{\n\t\tif (mesh->EmbeddedTextures.size() <= slot)\n\t\t\tmesh->EmbeddedTextures.resize(slot + 1);\n\t\tmesh->EmbeddedTextures[slot] = std::move(data);\n\t}\n", after=True, marker="setEmbeddedTexture")
edit("src/client/content_cao.cpp",
"\t\t\t\tif (texture_idx >= m_prop.textures.size())\n\t\t\t\t\tcontinue;\n\t\t\t\tstd::string texturestring = m_prop.textures[texture_idx];\n",
"\t\t\t\tstd::string texturestring;\n\t\t\t\tif (texture_idx < m_prop.textures.size())\n\t\t\t\t\ttexturestring = m_prop.textures[texture_idx];\n\t\t\t\tif (texturestring.empty()) {\n\t\t\t\t\t// Fall back to a texture embedded in the model file (.bbmodel)\n\t\t\t\t\ttexturestring = m_client->getEmbeddedTexture(m_prop.mesh,\n\t\t\t\t\t\t\tm_animated_meshnode->getMesh(), texture_idx);\n\t\t\t\t}\n", marker="getEmbeddedTexture")
edit("src/client/node_visuals.cpp",
"\t\t\tbool is_gltf = skinned_mesh->getSourceFormat() ==\n\t\t\t\t\tscene::SkinnedMesh::SourceFormat::GLTF;\n",
"\t\t\tconst auto src_format = skinned_mesh->getSourceFormat();\n\t\t\tbool is_gltf = src_format == scene::SkinnedMesh::SourceFormat::GLTF ||\n\t\t\t\t\tsrc_format == scene::SkinnedMesh::SourceFormat::BBMODEL;\n", marker="SourceFormat::BBMODEL")
edit("doc/lua_api.md", "(since version 5.10:) .gltf, .glb\n", "(since version 5.10:) .gltf, .glb, .bbmodel\n", marker=".glb, .bbmodel")
edit("doc/lua_api.md", "The .x, .b3d and .gltf formats additionally support (a single) animation.\n",
 "The .x and .b3d formats additionally support (a single) animation.\nThe .gltf and .bbmodel formats support multiple named animations.\n\n" + DOC + "\n", marker="#### Blockbench")
print("DONE" if not bad else "FAILED: %d problem(s)" % bad)
sys.exit(1 if bad else 0)
