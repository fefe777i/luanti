// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "IMeshLoader.h"
#include "path.h"

namespace scene
{

//! Loader for Blockbench (.bbmodel) models.
/**
 * Supported: cubes (box UV and per-face UV, rotation, inflate), mesh elements,
 * groups (bones) as joints, named animations (rotation, position, scale
 * keyframes) and textures embedded as base64 PNG.
 */
class CBBMeshFileLoader : public IMeshLoader
{
public:
	bool isALoadableFileExtension(const io::path &filename) const override;

	IAnimatedMesh *createMesh(io::IReadFile *file) override;
};

} // end namespace scene
