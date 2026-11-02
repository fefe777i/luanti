// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "CBBMeshFileLoader.h"

#include "SkinnedMesh.h"
#include "SSkinMeshBuffer.h"
#include "IAnimatedMesh.h"
#include "IReadFile.h"
#include "S3DVertex.h"
#include "coreutil.h"
#include "os.h"
#include "util/base64.h"

#include <json/json.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace scene
{

/*
 * Coordinate conventions
 * ----------------------
 * Blockbench: right-handed, +Y up, +X east, -Z north, 16 pixels per block,
 * the "front" of a model is its north (-Z) side.
 * Luanti:     left-handed, +Y up, the front of a mesh is -Z,
 * 10 units per node (like glTF, see lua_api.md).
 *
 * We convert by mirroring across X: (x, y, z) -> (-x, y, z) and scaling by
 * 10/16. This keeps the front at -Z and the left/right of the model intact.
 * Mirroring flips the winding order, which is handled when emitting faces.
 */

namespace
{

constexpr double UNIT_SCALE = 10.0 / 16.0;
constexpr double PI = 3.14159265358979323846;
constexpr size_t MAX_BUFFER_VERTICES = 65000;
constexpr int MAX_OUTLINER_DEPTH = 128;
constexpr size_t MAX_JOINTS = 60000;

using Vec = std::array<double, 3>;

struct Quat
{
	double x = 0, y = 0, z = 0, w = 1;
};

Quat qmul(const Quat &a, const Quat &b)
{
	return {
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	};
}

//! Blockbench Euler angles (degrees), order ZYX: R = Rz * Ry * Rx
Quat quatFromEuler(const Vec &deg)
{
	const double hx = deg[0] * PI / 360.0, hy = deg[1] * PI / 360.0,
			hz = deg[2] * PI / 360.0;
	const Quat qx{std::sin(hx), 0, 0, std::cos(hx)};
	const Quat qy{0, std::sin(hy), 0, std::cos(hy)};
	const Quat qz{0, 0, std::sin(hz), std::cos(hz)};
	return qmul(qz, qmul(qy, qx));
}

Vec rotate(const Quat &q, const Vec &v)
{
	// v' = v + 2w (u x v) + 2 u x (u x v), u = q.xyz
	const Vec u{q.x, q.y, q.z};
	auto cross = [](const Vec &a, const Vec &b) {
		return Vec{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
				a[0] * b[1] - a[1] * b[0]};
	};
	const Vec uv = cross(u, v);
	const Vec uuv = cross(u, uv);
	return {v[0] + 2 * (q.w * uv[0] + uuv[0]),
			v[1] + 2 * (q.w * uv[1] + uuv[1]),
			v[2] + 2 * (q.w * uv[2] + uuv[2])};
}

Vec operator+(const Vec &a, const Vec &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }
Vec operator-(const Vec &a, const Vec &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }

// Blockbench -> Luanti conversions

core::vector3df convPos(const Vec &p)
{
	return core::vector3df(static_cast<f32>(-p[0] * UNIT_SCALE),
			static_cast<f32>(p[1] * UNIT_SCALE),
			static_cast<f32>(p[2] * UNIT_SCALE));
}

core::vector3df convDir(const Vec &n)
{
	return core::vector3df(static_cast<f32>(-n[0]), static_cast<f32>(n[1]),
			static_cast<f32>(n[2]));
}

//! Mirroring across X turns the standard (right-handed) quaternion q into
//! (qx, -qy, -qz, w); Irrlicht stores rotations inversely to that.
core::quaternion convRot(const Quat &q)
{
	core::quaternion r(static_cast<f32>(-q.x), static_cast<f32>(q.y),
			static_cast<f32>(q.z), static_cast<f32>(q.w));
	r.normalize();
	return r;
}

double toNumber(const Json::Value &v, double def, bool *ok = nullptr)
{
	if (ok)
		*ok = true;
	if (v.isNumeric())
		return v.asDouble();
	if (v.isString()) {
		const std::string s = v.asString();
		char *end = nullptr;
		const double d = std::strtod(s.c_str(), &end);
		if (end != s.c_str() && *end == '\0')
			return d;
	}
	if (ok)
		*ok = false;
	return def;
}

bool toVec(const Json::Value &v, Vec &out)
{
	if (!v.isArray() || v.size() < 3)
		return false;
	for (int i = 0; i < 3; i++)
		out[i] = toNumber(v[i], 0.0);
	return true;
}

Vec getVec(const Json::Value &obj, const char *key, const Vec &def = {0, 0, 0})
{
	Vec out = def;
	if (obj.isObject() && obj.isMember(key))
		toVec(obj[key], out);
	return out;
}

struct Vertex
{
	Vec pos; // Blockbench units, relative to the joint pivot
	double u, v; // normalized
};

class Extractor
{
public:
	using SJoint = SkinnedMesh::SJoint;

	explicit Extractor(Json::Value &&root) :
			m_root(std::move(root)), m_builder(SkinnedMesh::SourceFormat::BBMODEL)
	{}

	SkinnedMesh *load()
	{
		if (!m_root.isObject())
			throw std::runtime_error("not a JSON object");

		const auto &res = m_root["resolution"];
		m_res_w = std::max(1.0, toNumber(res["width"], 16.0));
		m_res_h = std::max(1.0, toNumber(res["height"], 16.0));
		m_project_box_uv = m_root["meta"]["box_uv"].asBool();

		loadTextures();
		indexElements();

		// Everything hangs below an invisible root joint at the origin
		m_root_joint = m_builder.addJoint(nullptr);
		m_root_joint->transform = core::Transform{};
		m_root_joint->GlobalMatrix = core::matrix4();

		if (m_root["outliner"].isArray())
			loadOutliner(m_root["outliner"], m_root_joint, Vec{0, 0, 0}, 0);
		else
			warn("model has no outliner");

		flushBuffers();
		loadAnimations();
		return std::move(m_builder).finalize();
	}

	const std::vector<std::string> &getWarnings() const { return m_warnings; }

private:
	struct TexInfo
	{
		double uw, uh; // UV space size
	};

	struct GroupInfo
	{
		SJoint *joint;
		Vec rest_euler;
		core::vector3df rest_translation;
	};

	struct Accum
	{
		SJoint *joint;
		int texture;
		std::vector<video::S3DVertex> vertices;
		std::vector<u16> indices;
	};

	void warn(const std::string &msg)
	{
		if (m_warnings.size() < 32)
			m_warnings.push_back(msg);
	}

	void loadTextures()
	{
		const auto &textures = m_root["textures"];
		if (!textures.isArray())
			return;
		for (Json::ArrayIndex i = 0; i < textures.size(); i++) {
			const auto &tex = textures[i];
			TexInfo info{m_res_w, m_res_h};
			if (tex.isObject()) {
				const double uw = toNumber(tex["uv_width"], 0.0);
				const double uh = toNumber(tex["uv_height"], 0.0);
				if (uw > 0)
					info.uw = uw;
				if (uh > 0)
					info.uh = uh;

				const std::string src = tex["source"].isString() ?
						tex["source"].asString() : "";
				const size_t comma = src.find(',');
				if (src.compare(0, 5, "data:") == 0 && comma != std::string::npos &&
						src.find(";base64") < comma) {
					const std::string b64 = src.substr(comma + 1);
					if (base64_is_valid(b64)) {
						m_builder.setEmbeddedTexture(i, base64_decode(b64));
					} else {
						warn("texture " + std::to_string(i) + " has invalid base64 data");
					}
				} else if (!src.empty()) {
					warn("texture " + std::to_string(i) + " is not an embedded image");
				}
			}
			m_textures.push_back(info);
		}
	}

	void indexElements()
	{
		const auto &elements = m_root["elements"];
		if (!elements.isArray())
			return;
		for (Json::ArrayIndex i = 0; i < elements.size(); i++) {
			const auto &el = elements[i];
			if (el.isObject() && el["uuid"].isString())
				m_elements[el["uuid"].asString()] = &el;
		}
	}

	// Outliner: groups become joints, elements become rigidly attached meshes

	void loadOutliner(const Json::Value &list, SJoint *parent,
			const Vec &parent_origin, int depth)
	{
		if (depth > MAX_OUTLINER_DEPTH)
			throw std::runtime_error("outliner nesting too deep");

		for (Json::ArrayIndex i = 0; i < list.size(); i++) {
			const auto &item = list[i];
			if (item.isString()) {
				const auto it = m_elements.find(item.asString());
				if (it == m_elements.end()) {
					warn("outliner references unknown element " + item.asString());
					continue;
				}
				addElement(*it->second, parent, parent_origin);
			} else if (item.isObject()) {
				loadGroup(item, parent, parent_origin, depth);
			}
		}
	}

	void loadGroup(const Json::Value &group, SJoint *parent,
			const Vec &parent_origin, int depth)
	{
		if (group.isMember("export") && !group["export"].asBool())
			return;
		if (m_builder.getJoints().size() >= MAX_JOINTS)
			throw std::runtime_error("too many groups");

		const Vec origin = getVec(group, "origin");
		const Vec euler = getVec(group, "rotation");

		SJoint *joint = m_builder.addJoint(parent);
		if (group["name"].isString())
			joint->Name = group["name"].asString();

		core::Transform trs;
		trs.translation = convPos(origin - parent_origin);
		trs.rotation = convRot(quatFromEuler(euler));
		joint->transform = trs;
		const core::matrix4 local = trs.buildMatrix();
		joint->GlobalMatrix = parent ? parent->GlobalMatrix * local : local;

		if (group["uuid"].isString()) {
			m_groups[group["uuid"].asString()] =
					GroupInfo{joint, euler, trs.translation};
		}

		if (group["children"].isArray())
			loadOutliner(group["children"], joint, origin, depth + 1);
	}

	void addElement(const Json::Value &el, SJoint *joint, const Vec &group_origin)
	{
		if (el.isMember("export") && !el["export"].asBool())
			return;
		const std::string type = el["type"].isString() ? el["type"].asString() : "cube";
		if (type == "cube")
			addCube(el, joint, group_origin);
		else if (type == "mesh")
			addMeshElement(el, joint, group_origin);
		// Other element types (locators, null objects, ...) have no geometry.
	}

	Accum &getAccum(SJoint *joint, int texture)
	{
		const auto key = std::make_pair(joint, texture);
		const auto it = m_accum_index.find(key);
		if (it != m_accum_index.end() &&
				m_accums[it->second].vertices.size() + 4 <= MAX_BUFFER_VERTICES)
			return m_accums[it->second];
		m_accums.push_back(Accum{joint, texture, {}, {}});
		m_accum_index[key] = m_accums.size() - 1;
		return m_accums.back();
	}

	//! Emits a convex polygon. Vertices must be counter-clockwise when seen from
	//! outside (Blockbench space). Winding is reversed to compensate the mirroring.
	void addPolygon(int texture, SJoint *joint, const std::vector<Vertex> &poly,
			const Vec &normal)
	{
		if (poly.size() < 3 || poly.size() > 64)
			return;
		Accum &acc = getAccum(joint, texture);
		const u16 base = static_cast<u16>(acc.vertices.size());
		const core::vector3df n = convDir(normal);
		for (const auto &v : poly) {
			acc.vertices.emplace_back(convPos(v.pos), n,
					video::SColor(255, 255, 255, 255),
					core::vector2df(static_cast<f32>(v.u), static_cast<f32>(v.v)));
		}
		for (size_t i = 1; i + 1 < poly.size(); i++) {
			acc.indices.push_back(base + static_cast<u16>(i + 1));
			acc.indices.push_back(base + static_cast<u16>(i));
			acc.indices.push_back(base);
		}
	}

	// Returns the texture index of a face; -1 if the face is disabled.
	int faceTexture(const Json::Value &face) const
	{
		const auto &t = face["texture"];
		if (t.isIntegral())
			return std::max(0, t.asInt());
		if (t.isBool() && !t.asBool())
			return -1;
		return 0;
	}

	TexInfo texInfo(int texture) const
	{
		if (texture >= 0 && static_cast<size_t>(texture) < m_textures.size())
			return m_textures[texture];
		return TexInfo{m_res_w, m_res_h};
	}

	void addCube(const Json::Value &el, SJoint *joint, const Vec &group_origin)
	{
		Vec from = getVec(el, "from"), to = getVec(el, "to");
		const double inflate = toNumber(el["inflate"], 0.0);
		const Vec size = to - from;
		for (int i = 0; i < 3; i++) {
			from[i] -= inflate;
			to[i] += inflate;
		}
		const Vec origin = getVec(el, "origin");
		const Quat rot = quatFromEuler(getVec(el, "rotation"));
		const bool box_uv = el.isMember("box_uv") ? el["box_uv"].asBool() : m_project_box_uv;
		const bool mirror_uv = el["mirror_uv"].asBool();
		const double uo = el["uv_offset"].isArray() && el["uv_offset"].size() >= 2 ?
				toNumber(el["uv_offset"][0], 0.0) : 0.0;
		const double vo = el["uv_offset"].isArray() && el["uv_offset"].size() >= 2 ?
				toNumber(el["uv_offset"][1], 0.0) : 0.0;

		struct FaceDef
		{
			const char *name;
			Vec normal;
			// Corners TL, TR, BR, BL as seen from outside
			std::array<Vec, 4> corners;
		};
		const double x1 = from[0], y1 = from[1], z1 = from[2];
		const double x2 = to[0], y2 = to[1], z2 = to[2];
		const FaceDef faces[6] = {
			{"north", {0, 0, -1}, {Vec{x2, y2, z1}, Vec{x1, y2, z1}, Vec{x1, y1, z1}, Vec{x2, y1, z1}}},
			{"south", {0, 0, 1}, {Vec{x1, y2, z2}, Vec{x2, y2, z2}, Vec{x2, y1, z2}, Vec{x1, y1, z2}}},
			{"east", {1, 0, 0}, {Vec{x2, y2, z2}, Vec{x2, y2, z1}, Vec{x2, y1, z1}, Vec{x2, y1, z2}}},
			{"west", {-1, 0, 0}, {Vec{x1, y2, z1}, Vec{x1, y2, z2}, Vec{x1, y1, z2}, Vec{x1, y1, z1}}},
			{"up", {0, 1, 0}, {Vec{x1, y2, z1}, Vec{x2, y2, z1}, Vec{x2, y2, z2}, Vec{x1, y2, z2}}},
			{"down", {0, -1, 0}, {Vec{x1, y1, z2}, Vec{x2, y1, z2}, Vec{x2, y1, z1}, Vec{x1, y1, z1}}},
		};

		// Box UV layout (u1, v1, u2, v2) per face
		const double w = size[0], h = size[1], d = size[2];
		std::map<std::string, std::array<double, 4>> box;
		if (box_uv) {
			box["east"] = {uo, vo + d, uo + d, vo + d + h};
			box["north"] = {uo + d, vo + d, uo + d + w, vo + d + h};
			box["west"] = {uo + d + w, vo + d, uo + 2 * d + w, vo + d + h};
			box["south"] = {uo + 2 * d + w, vo + d, uo + 2 * d + 2 * w, vo + d + h};
			box["up"] = {uo + d, vo, uo + d + w, vo + d};
			box["down"] = {uo + d + w, vo + d, uo + d + 2 * w, vo};
			if (mirror_uv) {
				std::swap(box["east"], box["west"]);
				for (auto &kv : box)
					std::swap(kv.second[0], kv.second[2]);
			}
		}

		const auto &json_faces = el["faces"];
		for (const auto &def : faces) {
			if (!json_faces.isObject() || !json_faces[def.name].isObject())
				continue;
			const auto &face = json_faces[def.name];
			const int texture = faceTexture(face);
			if (texture < 0)
				continue;
			const TexInfo ti = texInfo(texture);

			std::array<double, 4> uv{0, 0, 0, 0};
			if (box_uv) {
				uv = box[def.name];
			} else if (face["uv"].isArray() && face["uv"].size() >= 4) {
				for (int i = 0; i < 4; i++)
					uv[i] = toNumber(face["uv"][i], 0.0);
			} else {
				continue;
			}
			// UV corners TL, TR, BR, BL
			const std::array<std::array<double, 2>, 4> uvc = {{
				{uv[0], uv[1]}, {uv[2], uv[1]}, {uv[2], uv[3]}, {uv[0], uv[3]}}};
			const int rot_steps = ((static_cast<int>(
					toNumber(face["rotation"], 0.0)) / 90) % 4 + 4) % 4;

			Vertex corner[4];
			for (int i = 0; i < 4; i++) {
				const auto &c = uvc[(i + 4 - rot_steps) % 4];
				const Vec p = origin + rotate(rot, def.corners[i] - origin);
				corner[i] = Vertex{p - group_origin, c[0] / ti.uw, c[1] / ti.uh};
			}
			// Canonical order: counter-clockwise seen from outside = TL, BL, BR, TR
			std::vector<Vertex> poly = {corner[0], corner[3], corner[2], corner[1]};
			addPolygon(texture, joint, poly, rotate(rot, Vec{def.normal}));
		}
	}

	void addMeshElement(const Json::Value &el, SJoint *joint, const Vec &group_origin)
	{
		const auto &verts = el["vertices"];
		const auto &faces = el["faces"];
		if (!verts.isObject() || !faces.isObject())
			return;
		const Vec origin = getVec(el, "origin");
		const Quat rot = quatFromEuler(getVec(el, "rotation"));

		for (const auto &fname : faces.getMemberNames()) {
			const auto &face = faces[fname];
			if (!face.isObject() || !face["vertices"].isArray())
				continue;
			const int texture = faceTexture(face);
			if (texture < 0)
				continue;
			const TexInfo ti = texInfo(texture);

			std::vector<Vertex> poly;
			for (const auto &vid : face["vertices"]) {
				if (!vid.isString())
					continue;
				Vec local;
				if (!toVec(verts[vid.asString()], local))
					continue;
				const Vec p = origin + rotate(rot, local);
				double u = 0, v = 0;
				const auto &uvj = face["uv"][vid.asString()];
				if (uvj.isArray() && uvj.size() >= 2) {
					u = toNumber(uvj[0], 0.0);
					v = toNumber(uvj[1], 0.0);
				}
				poly.push_back(Vertex{p - group_origin, u / ti.uw, v / ti.uh});
			}
			if (poly.size() < 3)
				continue;
			// Flat normal (counter-clockwise winding seen from outside)
			const Vec a = poly[1].pos - poly[0].pos, b = poly[2].pos - poly[0].pos;
			Vec n{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
					a[0] * b[1] - a[1] * b[0]};
			const double len = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
			if (len > 1e-9)
				n = {n[0] / len, n[1] / len, n[2] / len};
			addPolygon(texture, joint, poly, n);
		}
	}

	void flushBuffers()
	{
		for (auto &acc : m_accums) {
			if (acc.vertices.empty())
				continue;
			auto *buf = new SSkinMeshBuffer(std::move(acc.vertices), std::move(acc.indices));
			const u32 nr = m_builder.addMeshBuffer(buf);
			m_builder.setTextureSlot(nr, static_cast<u32>(acc.texture));
			acc.joint->AttachedMeshes.push_back(nr);
		}
		m_accums.clear();
		m_accum_index.clear();
	}

	// Animations

	void loadAnimations()
	{
		const auto &anims = m_root["animations"];
		if (!anims.isArray())
			return;
		for (Json::ArrayIndex i = 0; i < anims.size(); i++) {
			const auto &anim = anims[i];
			if (anim.isObject())
				loadAnimation(anim);
		}
	}

	void loadAnimation(const Json::Value &anim)
	{
		const u16 index = m_builder.addAnimation();
		auto &out = m_builder.getAnimation(index);
		out.name = anim["name"].isString() ? anim["name"].asString() : "";

		double max_time = 0;
		const auto &animators = anim["animators"];
		if (animators.isObject()) {
			for (const auto &uuid : animators.getMemberNames()) {
				const auto it = m_groups.find(uuid);
				if (it == m_groups.end())
					continue; // effects (sound, particles) or unknown objects
				const auto &animator = animators[uuid];
				if (!animator.isObject() || !animator["keyframes"].isArray())
					continue;
				SkinnedMesh::Animation::JointKeys jk;
				jk.joint_id = it->second.joint->JointID;
				max_time = std::max(max_time,
						loadKeyframes(animator["keyframes"], it->second, jk.keys, out.name));
				jk.keys.cleanup();
				if (!jk.keys.empty())
					out.joint_keys.push_back(std::move(jk));
			}
		}

		double length = toNumber(anim["length"], 0.0);
		out.end_frame = static_cast<f32>(std::max(length, max_time));
	}

	struct RawKey
	{
		double time;
		Vec value;
		bool step;
		bool has_post;
		Vec post;
	};

	//! @return the largest keyframe time
	double loadKeyframes(const Json::Value &keyframes, const GroupInfo &group,
			SkinnedMesh::Keys &keys, const std::string &anim_name)
	{
		std::vector<RawKey> chan[3]; // position, rotation, scale
		bool molang_warned = false;

		for (const auto &kf : keyframes) {
			if (!kf.isObject() || !kf["channel"].isString())
				continue;
			const std::string channel = kf["channel"].asString();
			int ch;
			if (channel == "position")
				ch = 0;
			else if (channel == "rotation")
				ch = 1;
			else if (channel == "scale")
				ch = 2;
			else
				continue;
			const auto &points = kf["data_points"];
			if (!points.isArray() || points.empty())
				continue;

			auto readPoint = [&](const Json::Value &p) {
				const double def = ch == 2 ? 1.0 : 0.0;
				Vec v{def, def, def};
				const char *names[3] = {"x", "y", "z"};
				for (int i = 0; i < 3; i++) {
					bool ok = true;
					v[i] = toNumber(p[names[i]], def, &ok);
					if (!ok && p.isMember(names[i]) && !p[names[i]].asString().empty() &&
							!molang_warned) {
						molang_warned = true;
						warn("animation " + anim_name + ": expressions in keyframes are not supported");
					}
				}
				return v;
			};

			RawKey key;
			key.time = toNumber(kf["time"], 0.0);
			key.value = readPoint(points[0]);
			key.step = kf["interpolation"].isString() && kf["interpolation"].asString() == "step";
			key.has_post = points.size() >= 2;
			if (key.has_post)
				key.post = readPoint(points[1]);
			chan[ch].push_back(key);
		}

		double max_time = 0;
		for (auto &list : chan) {
			std::stable_sort(list.begin(), list.end(),
					[](const RawKey &a, const RawKey &b) { return a.time < b.time; });
			if (!list.empty())
				max_time = std::max(max_time, list.back().time);
		}

		auto allStep = [](const std::vector<RawKey> &list) {
			return std::all_of(list.begin(), list.end(),
					[](const RawKey &k) { return k.step; });
		};
		keys.position.interpolate = !allStep(chan[0]);
		keys.rotation.interpolate = !allStep(chan[1]);
		keys.scale.interpolate = !allStep(chan[2]);

		constexpr double JUMP_EPS = 1e-4;

		// Position keys are offsets (in pixels) from the bone's rest position
		auto posValue = [&](const Vec &delta) {
			return group.rest_translation + convPos(delta);
		};
		// Rotation keys are Euler offsets added to the bone's rest rotation
		auto rotValue = [&](const Vec &delta) {
			return convRot(quatFromEuler(group.rest_euler + delta));
		};

		for (const auto &k : chan[0]) {
			keys.position.pushBack(static_cast<f32>(k.time), posValue(k.value));
			if (k.has_post)
				keys.position.pushBack(static_cast<f32>(k.time + JUMP_EPS), posValue(k.post));
		}
		for (const auto &k : chan[1]) {
			keys.rotation.pushBack(static_cast<f32>(k.time), rotValue(k.value));
			if (k.has_post)
				keys.rotation.pushBack(static_cast<f32>(k.time + JUMP_EPS), rotValue(k.post));
		}
		for (const auto &k : chan[2]) {
			keys.scale.pushBack(static_cast<f32>(k.time),
					core::vector3df(k.value[0], k.value[1], k.value[2]));
			if (k.has_post)
				keys.scale.pushBack(static_cast<f32>(k.time + JUMP_EPS),
						core::vector3df(k.post[0], k.post[1], k.post[2]));
		}
		return max_time;
	}

	Json::Value m_root;
	SkinnedMeshBuilder m_builder;
	SJoint *m_root_joint = nullptr;
	double m_res_w = 16, m_res_h = 16;
	bool m_project_box_uv = false;
	std::vector<TexInfo> m_textures;
	std::unordered_map<std::string, const Json::Value *> m_elements;
	std::unordered_map<std::string, GroupInfo> m_groups;
	std::vector<Accum> m_accums;
	std::map<std::pair<SJoint *, int>, size_t> m_accum_index;
	std::vector<std::string> m_warnings;
};

} // namespace

bool CBBMeshFileLoader::isALoadableFileExtension(const io::path &filename) const
{
	return core::hasFileExtension(filename, "bbmodel");
}

IAnimatedMesh *CBBMeshFileLoader::createMesh(io::IReadFile *file)
{
	const char *filename = file->getFileName().c_str();

	const long size = file->getSize();
	if (size <= 0 || size > 64L * 1024 * 1024) {
		os::Printer::log("bbmodel: invalid file size", filename, ELL_ERROR);
		return nullptr;
	}
	std::string text(static_cast<size_t>(size), '\0');
	if (file->read(text.data(), text.size()) != text.size()) {
		os::Printer::log("bbmodel: could not read file", filename, ELL_ERROR);
		return nullptr;
	}

	Json::Value root;
	{
		Json::CharReaderBuilder builder;
		std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
		std::string errs;
		if (!reader->parse(text.data(), text.data() + text.size(), &root, &errs)) {
			os::Printer::log("bbmodel: error parsing JSON", errs.c_str(), ELL_ERROR);
			return nullptr;
		}
	}

	try {
		Extractor extractor(std::move(root));
		SkinnedMesh *mesh = extractor.load();
		for (const auto &warning : extractor.getWarnings())
			os::Printer::log(filename, warning.c_str(), ELL_WARNING);
		return mesh;
	} catch (const std::exception &e) {
		os::Printer::log("bbmodel: error converting to mesh", e.what(), ELL_ERROR);
	}
	return nullptr;
}

} // end namespace scene
