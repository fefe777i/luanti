def apply(path, old, new, must_find=1):
    with open(path, 'r') as f:
        content = f.read()
    count = content.count(old)
    if count != must_find:
        print(f"ПОМИЛКА в {path}: очікував {must_find} збігів, знайшов {count}")
        print(f"--- шукав: ---\n{old}\n--- ---")
        return False
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print(f"OK: {path}")
    return True

ok = True

# ---------- src/client/wieldmesh.h ----------
# Add a public method to override the internal mesh node's scale,
# bypassing setItem()'s automatic shrink-to-hand-size behavior.

ok &= apply(
    "src/client/wieldmesh.h",
    "\tscene::IMesh *getMesh() { return m_meshnode->getMesh(); }\n\n\tvirtual void render();\n",
    "\tscene::IMesh *getMesh() { return m_meshnode->getMesh(); }\n\n"
    "\t// Overrides the internal child mesh node's scale directly, bypassing\n"
    "\t// setItem()'s automatic wield-size scaling. Used to display an item's\n"
    "\t// node mesh at full real-world (in-map) size instead of hand-held size,\n"
    "\t// e.g. for client-side \"ghost node\" build previews.\n"
    "\tvoid setStaticNodeScale(f32 scale) { m_meshnode->setScale(v3f(scale)); }\n\n"
    "\tvirtual void render();\n"
)

# ---------- src/client/client.cpp ----------
# Fix Client::setGhostNode to reset scale to full node size after setItem().

ok &= apply(
    "src/client/client.cpp",
    "\tItemStack item(node_name, 1, 0, idef());\n"
    "\tscenenode->setItem(item, this, false);\n\n"
    "\t// Semi-transparent white tint so the underlying node texture still\n"
    "\t// shows through, giving the classic \"ghost block\" preview look.\n"
    "\tscenenode->setColor(video::SColor(140, 255, 255, 255));\n\n"
    "\tscenenode->setPosition(intToFloat(pos, BS));\n"
    "\t// WieldMeshSceneNode is normally scaled down for hand display;\n"
    "\t// scale it back up to a full in-world node size.\n"
    "\tscenenode->setScale(v3f(1.5f, 1.5f, 1.5f));\n\n"
    "\tscenenode->drop(); // the scene manager already grabbed a reference\n",

    "\tItemStack item(node_name, 1, 0, idef());\n"
    "\tscenenode->setItem(item, this, false);\n\n"
    "\t// setItem() always shrinks node meshes down to hand-held \"wield\" size\n"
    "\t// internally; override that back to full real-world node size here.\n"
    "\tscenenode->setStaticNodeScale(1.0f);\n\n"
    "\t// Semi-transparent white tint so the underlying node texture still\n"
    "\t// shows through, giving the classic \"ghost block\" preview look.\n"
    "\tscenenode->setColor(video::SColor(140, 255, 255, 255));\n\n"
    "\tscenenode->setPosition(intToFloat(pos, BS));\n\n"
    "\tscenenode->drop(); // the scene manager already grabbed a reference\n"
)

print()
if ok:
    print("=== УСПІХ: масштаб фантомних блоків виправлено ===")
else:
    print("=== УВАГА: подивись помилки вище ===")
