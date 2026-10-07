// art-assets .drc → Godot 可用 .glb 转换器
//
// 【为什么需要这个脚本】art-assets 里的模型是某网页 3D 游戏的自定义管线产物：
//   标准 Draco 流 + 头部内嵌一段 "info" JSON 元数据（描述顶点属性表、动画 fps/帧数）。
//   Godot 不认 .drc，所以这里把整套资产解码并重建成 glTF 2.0：
//   - 角色包：mesh.drc（蒙皮网格）+ -bones.drc（关节层级 + 绑定姿势）
//             + -idle/-talk/-walk.drc（24fps 逐帧关节 TRS 点云）→ 单个带 skin+animation 的 .glb
//   - 静态网格：鸟 / 树叶 / 送货道具 / 行星分块 → 纯 mesh .glb
//
// 【元数据语义】（从文件头实测得出）
//   "type":0 = 三角网格；"type":1 = 点云
//   info.attributes 是【按 draco 属性下标排序】的 [名字, 内部类型码] 列表，
//   我们据此把属性下标映射到语义名（draco 自身的 attribute_name 未必写进文件）。
//   bones 属性：position/quaternion/scale/hierarchy(父关节下标)
//   动画属性：position/quaternion/scale + userData:{fps,frames}，点数 = frames × 关节数；
//   排布可能是「帧优先」或「关节优先」，用相邻点距启发式判定。
//
// 【TRS 是局部还是全局】bones/动画里的 TRS 无法从格式上区分局部/模型空间，
//   用判定法：把绑定 TRS 当作局部沿 hierarchy 合成出全局关节位置，
//   与网格顶点 AABB 比较，取更吻合的解释，必要时统一换算成 glTF 的局部 TRS。
//
// 用法：node tools/art_convert/convert.mjs
//
// 【依赖选择】必须用通用包 draco3d 而不是 draco3dgltf：
//   draco3dgltf 的 wasm 构建是 glTF 专用版，不含点云解码器——bones/动画/曲线
//   这些点云文件会报 "Unsupported geometry type."。

import { createDecoderModule } from 'draco3d';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'art-assets', 'models');
const OUT_NPC = path.join(ROOT, 'assets', 'art', 'npcs');
const OUT_ENV = path.join(ROOT, 'assets', 'art', 'env');

// ---------------- 基础工具 ----------------

/** 从 .drc 字节流里抠出内嵌 "info" JSON。
 *  metadata 块：条目数 varint、键长 varint "info"、值长 varint、JSON 文本。
 *  不逐字节解 varint——直接定位 '{' 做括号配对，对这批文件足够稳。 */
function extractInfoJson(bytes) {
	const n = Math.min(bytes.length, 512);
	for (let i = 0; i < n - 4; i++) {
		if (bytes[i] === 0x69 && bytes[i + 1] === 0x6e && bytes[i + 2] === 0x66 && bytes[i + 3] === 0x6f) {
			const start = bytes.indexOf(0x7b, i);
			if (start < 0) return null;
			let depth = 0;
			for (let j = start; j < bytes.length; j++) {
				if (bytes[j] === 0x7b) depth++;
				else if (bytes[j] === 0x7d) {
					depth--;
					if (depth === 0) return JSON.parse(new TextDecoder().decode(bytes.subarray(start, j + 1)));
				}
			}
		}
	}
	return null;
}

/** GLB 二进制段构建器：记录 bufferView（写入前按 4 字节对齐）。 */
class Bin {
	constructor() { this.views = []; this.chunks = []; this.len = 0; }
	add(typedArr) {
		const pad = (4 - (this.len % 4)) % 4;
		if (pad) { this.chunks.push(new Uint8Array(pad)); this.len += pad; }
		const bytes = new Uint8Array(typedArr.buffer, typedArr.byteOffset, typedArr.byteLength);
		this.chunks.push(bytes);
		this.views.push({ buffer: 0, byteOffset: this.len, byteLength: bytes.byteLength });
		this.len += bytes.byteLength;
		return this.views.length - 1; // bufferView 索引
	}
	finish() {
		const out = new Uint8Array(this.len);
		let off = 0;
		for (const c of this.chunks) { out.set(c, off); off += c.byteLength; }
		return out;
	}
}

const COMPONENT_TYPE = { Int8Array: 5120, Uint8Array: 5121, Int16Array: 5122, Uint16Array: 5123, Uint32Array: 5125, Float32Array: 5126 };

const mat4 = {
	mul(a, b) {
		const o = new Array(16).fill(0);
		for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++)
			for (let k = 0; k < 4; k++) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
		return o;
	},
	invert(m) {
		const inv = new Array(16);
		const a00 = m[0], a01 = m[1], a02 = m[2], a03 = m[3];
		const a10 = m[4], a11 = m[5], a12 = m[6], a13 = m[7];
		const a20 = m[8], a21 = m[9], a22 = m[10], a23 = m[11];
		const a30 = m[12], a31 = m[13], a32 = m[14], a33 = m[15];
		const b00 = a00 * a11 - a01 * a10, b01 = a00 * a12 - a02 * a10, b02 = a00 * a13 - a03 * a10;
		const b03 = a01 * a12 - a02 * a11, b04 = a01 * a13 - a03 * a11, b05 = a02 * a13 - a03 * a12;
		const b06 = a20 * a31 - a21 * a30, b07 = a20 * a32 - a22 * a30, b08 = a20 * a33 - a23 * a30;
		const b09 = a21 * a32 - a22 * a31, b10 = a21 * a33 - a23 * a31, b11 = a22 * a33 - a23 * a32;
		const det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
		if (!det) return mat4.identity();
		const d = 1 / det;
		return [
			(a11 * b11 - a12 * b10 + a13 * b09) * d, (a02 * b10 - a01 * b11 - a03 * b09) * d,
			(a31 * b05 - a32 * b04 + a33 * b03) * d, (a22 * b04 - a21 * b05 - a23 * b03) * d,
			(a12 * b08 - a10 * b11 - a13 * b07) * d, (a00 * b11 - a02 * b08 + a03 * b07) * d,
			(a32 * b02 - a30 * b05 - a33 * b01) * d, (a20 * b05 - a22 * b02 + a23 * b01) * d,
			(a10 * b10 - a11 * b08 + a13 * b06) * d, (a01 * b08 - a00 * b10 - a03 * b06) * d,
			(a30 * b04 - a31 * b02 + a33 * b00) * d, (a21 * b02 - a20 * b04 - a23 * b00) * d,
			(a11 * b07 - a10 * b09 - a12 * b06) * d, (a00 * b09 - a01 * b07 + a02 * b06) * d,
			(a31 * b01 - a30 * b03 - a32 * b00) * d, (a20 * b03 - a21 * b01 + a22 * b00) * d,
		];
	},
	identity: () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
	fromTRS(t, q, s) {
		const [x, y, z, w] = q, [sx, sy, sz] = s;
		const x2 = x + x, y2 = y + y, z2 = z + z;
		const xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2;
		const wx = w * x2, wy = w * y2, wz = w * z2;
		return [
			(1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
			(xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
			(xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
			t[0], t[1], t[2], 1,
		];
	},
};

/** 列主序矩阵 → {t,q,s}（假定无剪切；这批资产只有 TRS）。 */
function trsFromMat(m) {
	const t = [m[12], m[13], m[14]];
	const sx = Math.hypot(m[0], m[1], m[2]), sy = Math.hypot(m[4], m[5], m[6]), sz = Math.hypot(m[8], m[9], m[10]);
	const m00 = m[0] / sx, m01 = m[4] / sy, m02 = m[8] / sz;
	const m10 = m[1] / sx, m11 = m[5] / sy, m12 = m[9] / sz;
	const m20 = m[2] / sx, m21 = m[6] / sy, m22 = m[10] / sz;
	const tr = m00 + m11 + m22;
	let x, y, z, w;
	if (tr > 0) { const S = Math.sqrt(tr + 1) * 2; w = S / 4; x = (m21 - m12) / S; y = (m02 - m20) / S; z = (m10 - m01) / S; }
	else if (m00 > m11 && m00 > m22) { const S = Math.sqrt(1 + m00 - m11 - m22) * 2; w = (m21 - m12) / S; x = S / 4; y = (m01 + m10) / S; z = (m02 + m20) / S; }
	else if (m11 > m22) { const S = Math.sqrt(1 + m11 - m00 - m22) * 2; w = (m02 - m20) / S; x = (m01 + m10) / S; y = S / 4; z = (m12 + m21) / S; }
	else { const S = Math.sqrt(1 + m22 - m00 - m11) * 2; w = (m10 - m01) / S; x = (m02 + m20) / S; y = (m12 + m21) / S; z = S / 4; }
	return { t, q: [x, y, z, w], s: [sx, sy, sz] };
}

async function main() {
	const mod = await createDecoderModule();
	const decoder = new mod.Decoder();

	// ---------------- Draco 解码 ----------------

	function decodeDrc(file) {
		const bytes = fs.readFileSync(file);
		const info = extractInfoJson(bytes);
		const buf = new mod.DecoderBuffer();
		buf.Init(new Int8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength), bytes.length);
		const geomType = decoder.GetEncodedGeometryType(buf);
		let geom, status;
		if (geomType === mod.TRIANGULAR_MESH) {
			geom = new mod.Mesh();
			status = decoder.DecodeBufferToMesh(buf, geom);
		} else {
			geom = new mod.PointCloud();
			status = decoder.DecodeBufferToPointCloud(buf, geom);
		}
		if (!status.ok() || !geom) throw new Error('Draco 解码失败: ' + (status ? status.error_msg() : 'null'));
		return { geom, info, isMesh: geomType === mod.TRIANGULAR_MESH };
	}

	/** info.attributes[i][0] 是 draco 第 i 个属性的语义名（顺序即文件内属性顺序）。 */
	function attrByName(geom, info, wanted) {
		const list = info && Array.isArray(info.attributes) ? info.attributes : null;
		for (let i = 0; i < geom.num_attributes(); i++) {
			let name = null;
			if (list && list[i]) name = list[i][0];
			else {
				try { name = decoder.GetAttributeByUniqueId(geom, i).attribute_name(); } catch { /* 无名属性 */ }
			}
			if (name && wanted.includes(name)) {
				const attr = decoder.GetAttribute(geom, i);
				const comps = attr.num_components();
				const npts = geom.num_points();
				const dt = attr.data_type();
				// 【必须走指针版 API】GetAttributeFloatForAllPoints 这类 typed helper
				// 在这批文件上会「成功返回但填零」——只有指针版拿到的是真实数据。
				// 枚举值不写死（不同构建 DT_* 数值不同），从模块常量反查。
				const kinds = [
					['DT_INT8', 1, Int8Array], ['DT_UINT8', 1, Uint8Array],
					['DT_INT16', 2, Int16Array], ['DT_UINT16', 2, Uint16Array],
					['DT_INT32', 4, Int32Array], ['DT_UINT32', 4, Uint32Array],
					['DT_FLOAT32', 4, Float32Array],
				];
				const kind = kinds.find(k => mod[k[0]] === dt) || kinds[6];
				const bytes = npts * comps * kind[1];
				const ptr = mod._malloc(bytes);
				try {
					if (!decoder.GetAttributeDataArrayForAllPoints(geom, attr, dt, bytes, ptr)) {
						throw new Error(`属性 ${name} 读取失败`);
					}
					// emscripten 堆视图按类型取名；malloc 之后没有再分配，堆地址稳定
					const heapName = { Int8Array: 'HEAP8', Uint8Array: 'HEAPU8', Int16Array: 'HEAP16', Uint16Array: 'HEAPU16', Int32Array: 'HEAP32', Uint32Array: 'HEAPU32', Float32Array: 'HEAPF32' }[kind[2].name];
					const data = new kind[2](mod[heapName].buffer, ptr, npts * comps).slice();
					return { comps, data };
				} finally { mod._free(ptr); }
			}
		}
		return null;
	}

	/** 网格三角形索引：优先批量 API（快），退化逐面读（稳）。 */
	function readIndices(geom) {
		const numFaces = geom.num_faces();
		const out = new Uint32Array(numFaces * 3);
		if (typeof decoder.GetTrianglesUInt32Array === 'function' && typeof mod._malloc === 'function') {
			const ptr = mod._malloc(numFaces * 4);
			try {
				if (decoder.GetTrianglesUInt32Array(geom, numFaces * 3, ptr)) {
					out.set(new Uint32Array(mod.HEAPU32.buffer, ptr, numFaces * 3));
					return out;
				}
			} finally { mod._free(ptr); }
		}
		const face = new mod.DracoInt32Array();
		for (let f = 0; f < numFaces; f++) {
			decoder.GetFaceFromMesh(geom, f, face);
			out[f * 3] = face.GetValue(0); out[f * 3 + 1] = face.GetValue(1); out[f * 3 + 2] = face.GetValue(2);
		}
		return out;
	}

	function aabbOf(attr, npts) {
		const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
		for (let i = 0; i < npts; i++) for (let c = 0; c < 3; c++) {
			const v = attr.data[i * 3 + c];
			mn[c] = Math.min(mn[c], v); mx[c] = Math.max(mx[c], v);
		}
		return { min: mn, max: mx };
	}

	/** 分量数不足 4 时补齐（JOINTS/WEIGHTS 必须是 VEC4）。 */
	function pad4(src, comps, fill) {
		if (comps === 4) return src;
		const n = src.length / comps;
		const out = new (src.constructor)(n * 4);
		for (let i = 0; i < n; i++) {
			for (let c = 0; c < comps; c++) out[i * 4 + c] = src[i * comps + c];
			out[i * 4 + 3] = fill;
		}
		return out;
	}

	// ---------------- glTF 写出 ----------------

	const manifest = { files: {} };
	const fails = [];

	/** 把已解码网格加进 glb 组装器 g，返回 {meshIndex, surfaces, aabb}。
	 *  surfaceId 相同的连续三角合并成一个 primitive + 一个材质 m0/m1/...，
	 *  Godot 侧按材质名查调色板上色。skinned=true 时补 JOINTS_0/WEIGHTS_0。
	 *  分区数超过 maxSurfaces 时（星球地形把每块地皮编成独立 surfaceId），
	 *  改走「顶点色」模式、全部面合并成单材质，避免 Godot 导入出几千个材质资源。
	 *  dataVcol=true（planets_* 星球族）：COLOR_0 不再哈希，而是原样写回
	 *  (surfaceId, batchId, elementId, 1) 三个标量 —— 原版地形材质要用它们：
	 *  surfaceId 参与描边/岩石条纹，elementId==1 是山体（草地掩码），
	 *  水面的 batchId 是烘焙的离岸距离（波浪/浅滩渐变），树叶的 leavescolor
	 *  是 16×16 调色板索引。Godot 侧 island_materials.gd 按同样语义读取。 */
	function addMesh(g, decoded, name, skinned, maxSurfaces = 128, dataVcol = false) {
		const { geom, info } = decoded;
		const npts = geom.num_points();
		const idx = readIndices(geom);
		const pos = attrByName(geom, info, ['position']);
		if (!pos) throw new Error('缺 position 属性');
		const nrm = attrByName(geom, info, ['normal']);
		const uv = attrByName(geom, info, ['uv']);
		const sid = attrByName(geom, info, ['surfaceId']);
		const bid = dataVcol ? attrByName(geom, info, ['batchId']) : null;
		const eid = dataVcol ? attrByName(geom, info, ['elementId']) : null;
		const lcol = dataVcol ? attrByName(geom, info, ['leavescolor']) : null;
		const jidx = skinned ? attrByName(geom, info, ['skinIndex']) : null;
		const jw = skinned ? attrByName(geom, info, ['skinWeight']) : null;

		const aabb = aabbOf(pos, npts);
		const pushAcc = (data, type, count, extra = {}) => {
			const bv = g.bin.add(data);
			g.accessors.push({
				bufferView: bv, componentType: extra.componentType || COMPONENT_TYPE[data.constructor.name],
				count, type, normalized: extra.normalized, min: extra.min, max: extra.max,
			});
			return g.accessors.length - 1;
		};

		// 先统计 surfaceId 分区数，决定走「分区材质」还是「顶点色合并」
		const surfaces = [];
		if (sid) {
			for (const v of idx) { const s = sid.data[v]; if (!surfaces.includes(s)) surfaces.push(s); }
			surfaces.sort((a, b) => a - b);
		} else surfaces.push(0);
		const vcolMode = surfaces.length > maxSurfaces;

		// 每个分区的平均高度（面首顶点累计）→ 归一化到 [0,1]，供人形启发式调色。
		// 原游戏把调色映射放在网页层（CSS/JSON），模型里只有无语义的槽号；
		// 高度是唯一可用的语义线索：头带/上衣带/裤带/鞋带各配一组协调色轮换。
		const slotY = {}, slotN = {};
		if (skinned && sid) {
			for (let f = 0; f < idx.length; f += 3) {
				const v = idx[f], s = sid.data[v];
				slotY[s] = (slotY[s] || 0) + pos.data[v * 3 + 1];
				slotN[s] = (slotN[s] || 0) + 1;
			}
		}
		const slotH01 = (s) => slotN[s]
			? (slotY[s] / slotN[s] - aabb.min[1]) / Math.max(0.001, aabb.max[1] - aabb.min[1])
			: 0.5;

		const attributes = { POSITION: pushAcc(pos.data, 'VEC3', npts, { min: aabb.min, max: aabb.max }) };
		if (nrm) attributes.NORMAL = pushAcc(nrm.data, 'VEC3', npts);
		if (uv) attributes.TEXCOORD_0 = pushAcc(uv.data, 'VEC2', npts);
		if (vcolMode) {
			if (dataVcol) {
				// 星球族：COLOR_0 = (surfaceId, batchId, elementId, 1) 原始标量。
				// 没有对应属性的通道补 0（树叶用 r=leavescolor 调色板索引，水面用 g=离岸距离）。
				const cdata = new Float32Array(npts * 4);
				for (let p = 0; p < npts; p++) {
					cdata[p * 4] = sid ? sid.data[p] : (lcol ? lcol.data[p] : 0);
					cdata[p * 4 + 1] = bid ? bid.data[p] : 0;
					cdata[p * 4 + 2] = eid ? eid.data[p] : 0;
					cdata[p * 4 + 3] = 1;
				}
				attributes.COLOR_0 = pushAcc(cdata, 'VEC4', npts);
			} else {
				// surfaceId 哈希成稳定颜色（黄金比例取色相 + 低模平涂饱和度/亮度）
				const cdata = new Float32Array(npts * 4);
				const cache = {};
				for (let p = 0; p < npts; p++) {
					const s = sid.data[p];
					let c = cache[s];
					if (!c) { c = hslToRgb((s * 0.61803398875) % 1, 0.52, 0.68); cache[s] = c; }
					cdata[p * 4] = c[0]; cdata[p * 4 + 1] = c[1]; cdata[p * 4 + 2] = c[2]; cdata[p * 4 + 3] = 1;
				}
				attributes.COLOR_0 = pushAcc(cdata, 'VEC4', npts);
			}
		} else if (dataVcol && (sid || bid || eid || lcol)) {
			// 星球族里分区数没超阈值的（水面/树叶/VFX 等）：同样把标量塞进 COLOR_0，
			// 语义与 vcolMode 分支一致；没有 sid 时 r 依次退到 leavescolor / batchId。
			const cdata = new Float32Array(npts * 4);
			for (let p = 0; p < npts; p++) {
				cdata[p * 4] = sid ? sid.data[p] : (lcol ? lcol.data[p] : (bid ? bid.data[p] : 0));
				cdata[p * 4 + 1] = bid ? bid.data[p] : 0;
				cdata[p * 4 + 2] = eid ? eid.data[p] : 0;
				cdata[p * 4 + 3] = 1;
			}
			attributes.COLOR_0 = pushAcc(cdata, 'VEC4', npts);
		}
		// leavescolor（tree-leaves 才有，comps=1 的 Int32 小整数 0/2/…）：不是颜色，
		// 是拿不到映射表的调色索引，原样写进 COLOR_0 会让 glTF 非法 —— 直接丢弃，
		// 上色交给 Godot 侧 tint（树叶绿）。
		if (skinned) {
			attributes.JOINTS_0 = pushAcc(pad4(jidx.data, jidx.comps, 0), 'VEC4', npts);
			attributes.WEIGHTS_0 = pushAcc(pad4(jw.data, jw.comps, 0), 'VEC4', npts);
		}

		const prims = vcolMode
			? (() => {
					// 单 primitive 全部面 + 白底材质：Godot 检测到 COLOR_0 自动启用顶点色
					const iAcc = pushAcc(idx, 'SCALAR', idx.length);
					g.materials.push({ name: 'm0', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 1 } });
					return [{ attributes: { ...attributes }, indices: iAcc, material: g.materials.length - 1, mode: 4 }];
				})()
			: surfaces.map((s, si) => {
					const tri = [];
					for (let f = 0; f < idx.length; f += 3) {
						if (sid && sid.data[idx[f]] !== s) continue;
						tri.push(idx[f], idx[f + 1], idx[f + 2]);
					}
					const iAcc = pushAcc(new Uint32Array(tri), 'SCALAR', tri.length);
					// 角色用槽位高度调色；静态物件保持灰白占位（Godot 侧按 m<si> 查调色板）
					const base = (skinned && sid) ? slotBodyColor(si, slotH01(s)) : [0.82, 0.8, 0.78, 1];
					g.materials.push({ name: `m${si}`, pbrMetallicRoughness: { baseColorFactor: base, metallicFactor: 0, roughnessFactor: 1 } });
					return { attributes: { ...attributes }, indices: iAcc, material: g.materials.length - 1, mode: 4 };
				});

		g.meshes.push({ name, primitives: prims });
		return { meshIndex: g.meshes.length - 1, surfaces: vcolMode ? 1 : surfaces.length, aabb };
	}

	/** h∈[0,1) → RGB，用于 surfaceId 稳定取色 */
	function hslToRgb(h, s, l) {
		const f = (n) => {
			const k = (n + h * 12) % 12;
			return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
		};
		return [f(0), f(8), f(4)];
	}

	// ---- 人形槽位调色的色带（0xRRGGBB → [r,g,b,1]）----
	// 低模平涂观感：上衣鲜艳、下身沉稳、头带只交替肤色/发色。
	const C4 = (n) => [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, 1];
	const TOPS = [0xd97f7f, 0x5b8def, 0xe6b84c, 0x7fb069, 0xf2efe6, 0xc96f4a, 0x8a7fbf, 0x5fa8a0];
	const PANTS = [0x3a4258, 0x5c5346, 0x4a4a52, 0x2f4858];
	const SHOES = [0x2b2b33, 0x6b4f3a];
	/** 槽位平均高度 h01 ∈[0,1] → 部位色。si 参与轮换避免同带一片同色。 */
	function slotBodyColor(si, h01) {
		if (h01 > 0.82) return C4(si % 3 === 0 ? 0x3a2e28 : 0xf2c9a0);   // 头带：发色/肤色交替
		if (h01 > 0.45) return C4(TOPS[si % TOPS.length]);               // 上身
		if (h01 > 0.22) return C4(PANTS[si % PANTS.length]);             // 下身
		return C4(SHOES[si % SHOES.length]);                             // 脚
	}

	function packAndWrite(outPath, g, sceneNodes, extraJson = {}) {
		const bin = g.bin.finish();
		const json = {
			asset: { version: '2.0', generator: 'langcity-art-convert' },
			scene: 0, scenes: [{ nodes: sceneNodes }],
			nodes: g.nodes, meshes: g.meshes, accessors: g.accessors, materials: g.materials,
			bufferViews: g.bin.views, buffers: [{ byteLength: bin.length }], ...extraJson,
		};
		fs.writeFileSync(outPath, packGLB(json, bin));
	}

	/** 静态网格 .glb（分区阈值 48：deliveries 21 槽保留分区，星球地形转顶点色）。
	 *  planets_* 星球族额外走 dataVcol：COLOR_0 写回原始 surfaceId/batchId/elementId。 */
	function writeStatic(outPath, decoded, glbName) {
		const g = { bin: new Bin(), accessors: [], materials: [], meshes: [], nodes: [] };
		const r = addMesh(g, decoded, glbName, false, 48, glbName.startsWith('planets_'));
		g.nodes.push({ name: glbName, mesh: r.meshIndex });
		packAndWrite(outPath, g, [0]);
		manifest.files[glbName + '.glb'] = { kind: 'static', surfaces: r.surfaces, anims: [], aabb: [...r.aabb.min, ...r.aabb.max] };
		return r;
	}

	/** 角色包 → 带 skin + animations 的 .glb（见文件头注释）。 */
	function writeCharacter(outPath, grp) {
		const meshDec = decodeDrc(grp.mesh);
		const bonesDec = decodeDrc(grp.bones);
		const bg = bonesDec.geom;
		const J = bg.num_points();
		const bPos = attrByName(bg, bonesDec.info, ['position']);
		const bQuat = attrByName(bg, bonesDec.info, ['quaternion']);
		const bScale = attrByName(bg, bonesDec.info, ['scale']);
		const bHier = attrByName(bg, bonesDec.info, ['hierarchy']);

		const parent = new Int32Array(J);
		let rootJ = 0;
		for (let j = 0; j < J; j++) {
			const h = bHier ? bHier.data[j] : -1;
			parent[j] = (h === j || h < 0) ? -1 : h;
			if (parent[j] < 0) rootJ = j;
		}

		const bind = [];
		for (let j = 0; j < J; j++)
			bind.push({
				t: [bPos.data[j * 3], bPos.data[j * 3 + 1], bPos.data[j * 3 + 2]],
				q: [bQuat.data[j * 4], bQuat.data[j * 4 + 1], bQuat.data[j * 4 + 2], bQuat.data[j * 4 + 3]],
				s: [bScale.data[j * 3], bScale.data[j * 3 + 1], bScale.data[j * 3 + 2]],
			});

		// 判定 TRS 约定：两种解释合成全局关节位置，与网格 AABB 比较，误差小的赢
		function jointGlobals(asLocal) {
			const gm = new Array(J), out = [];
			for (let j = 0; j < J; j++) {
				const local = mat4.fromTRS(bind[j].t, bind[j].q, bind[j].s);
				gm[j] = (asLocal && parent[j] >= 0) ? mat4.mul(gm[parent[j]], local) : local;
				out.push([gm[j][12], gm[j][13], gm[j][14]]);
			}
			return { gm, out };
		}
		const meshAabb = aabbOf(attrByName(meshDec.geom, meshDec.info, ['position']), meshDec.geom.num_points());
		function aabbGap(pos) {
			let gap = 0;
			for (let c = 0; c < 3; c++) {
				let mn = Infinity, mx = -Infinity;
				for (const p of pos) { mn = Math.min(mn, p[c]); mx = Math.max(mx, p[c]); }
				gap += Math.max(0, meshAabb.min[c] - mx) + Math.max(0, mn - meshAabb.min[c]);
			}
			return gap;
		}
		const gLocal = jointGlobals(true), gGlobal = jointGlobals(false);
		const asLocal = aabbGap(gLocal.out) <= aabbGap(gGlobal.out) + 1e-9;

		// 绑定姿势统一转成「局部 TRS」（glTF 原生约定）
		const localBind = [];
		if (asLocal) {
			for (let j = 0; j < J; j++) localBind.push(bind[j]);
		} else {
			for (let j = 0; j < J; j++) {
				const l = parent[j] >= 0 ? mat4.mul(mat4.invert(gGlobal.gm[parent[j]]), gGlobal.gm[j]) : gGlobal.gm[j];
				localBind.push(trsFromMat(l));
			}
		}

		// ---- 组装 glTF ----
		const g = { bin: new Bin(), accessors: [], materials: [], meshes: [], nodes: [], skins: [], animations: [] };
		const r = addMesh(g, meshDec, grp.name, true);

		const jointNode = [];
		for (let j = 0; j < J; j++) {
			g.nodes.push({ name: `j${j}`, translation: localBind[j].t, rotation: localBind[j].q, scale: localBind[j].s, children: [] });
			jointNode.push(g.nodes.length - 1);
		}
		const roots = [];
		for (let j = 0; j < J; j++) {
			if (parent[j] >= 0) g.nodes[jointNode[parent[j]]].children.push(jointNode[j]);
			else roots.push(jointNode[j]);
		}

		// inverseBindMatrices：从局部绑定 TRS 合成全局再取逆（约定无关，恒正确）
		const gmBind = [];
		for (let j = 0; j < J; j++) {
			const local = mat4.fromTRS(localBind[j].t, localBind[j].q, localBind[j].s);
			gmBind.push(parent[j] >= 0 ? mat4.mul(gmBind[parent[j]], local) : local);
		}
		const ibm = new Float32Array(J * 16);
		for (let j = 0; j < J; j++) ibm.set(mat4.invert(gmBind[j]), j * 16);
		const ibmBv = g.bin.add(ibm);
		g.accessors.push({ bufferView: ibmBv, componentType: 5126, count: J, type: 'MAT4' });
		g.skins.push({ inverseBindMatrices: g.accessors.length - 1, joints: jointNode, skeleton: jointNode[rootJ] });

		g.nodes.push({ name: grp.name, mesh: r.meshIndex, skin: 0 });
		const meshNode = g.nodes.length - 1;

		// ---- 动画 ----
		for (let ai = 0; ai < grp.anims.length; ai++) {
			const dec = decodeDrc(grp.anims[ai]);
			const ud = dec.info && dec.info.userData ? dec.info.userData : {};
			const frames = ud.frames || 0, fps = ud.fps || 24;
			const N = dec.geom.num_points();
			if (!frames || N !== frames * J) {
				console.warn(`  跳过动画 ${grp.animNames[ai]}：点数 ${N} ≠ 帧 ${frames} × 关节 ${J}`);
				continue;
			}
			const aPos = attrByName(dec.geom, dec.info, ['position']);
			const aQuat = attrByName(dec.geom, dec.info, ['quaternion']);
			const aScale = attrByName(dec.geom, dec.info, ['scale']);
			const order = detectOrder(aPos.data, N, J);

			// 每帧每关节先收集 TRS；源若为模型空间则换算局部，最后统一写通道
			const idxOf = (f, j) => (order === 'frame' ? f * J + j : j * frames + f);
			const framesLocal = [];
			for (let f = 0; f < frames; f++) {
				const gm = [];
				for (let j = 0; j < J; j++) {
					const p = idxOf(f, j);
					const src = {
						t: [aPos.data[p * 3], aPos.data[p * 3 + 1], aPos.data[p * 3 + 2]],
						q: [aQuat.data[p * 4], aQuat.data[p * 4 + 1], aQuat.data[p * 4 + 2], aQuat.data[p * 4 + 3]],
						s: [aScale.data[p * 3], aScale.data[p * 3 + 1], aScale.data[p * 3 + 2]],
					};
					const m = mat4.fromTRS(src.t, src.q, src.s);
					gm.push(asLocal ? null : m);
					framesLocal.push({ f, j, trs: asLocal ? src : null, m });
				}
				if (!asLocal) {
					for (let j = 0; j < J; j++) {
						const l = parent[j] >= 0 ? mat4.mul(mat4.invert(gm[parent[j]]), gm[j]) : gm[j];
						framesLocal.push({ f, j, trs: trsFromMat(l) });
					}
				}
			}
			// 重排成 [joint][frame]
			const seq = [];
			for (let j = 0; j < J; j++) seq.push(new Array(frames));
			for (const it of framesLocal) if (it.trs) seq[it.j][it.f] = it.trs;

			const times = new Float32Array(frames);
			for (let f = 0; f < frames; f++) times[f] = f / fps;
			const tAcc = (() => { const bv = g.bin.add(times); g.accessors.push({ bufferView: bv, componentType: 5126, count: frames, type: 'SCALAR' }); return g.accessors.length - 1; })();

			const channels = [], samplers = [];
			const writeCh = (prop, comps, pick) => {
				for (let j = 0; j < J; j++) {
					const out = new Float32Array(frames * comps);
					for (let f = 0; f < frames; f++) {
						const trs = seq[j][f];
						for (let c = 0; c < comps; c++) out[f * comps + c] = pick(trs)[c];
					}
					if (prop === 'rotation') fixQuatContinuity(out, frames);
					const bv = g.bin.add(out);
					g.accessors.push({ bufferView: bv, componentType: 5126, count: frames, type: comps === 4 ? 'VEC4' : 'VEC3' });
					samplers.push({ input: tAcc, output: g.accessors.length - 1, interpolation: 'LINEAR' });
					channels.push({ sampler: samplers.length - 1, target: { node: jointNode[j], path: prop } });
				}
			};
			writeCh('translation', 3, trs => trs.t);
			writeCh('rotation', 4, trs => trs.q);
			writeCh('scale', 3, trs => trs.s);
			g.animations.push({ name: grp.animNames[ai], channels, samplers });
		}

		packAndWrite(outPath, g, roots.concat([meshNode]), { skins: g.skins, animations: g.animations });
		manifest.files[grp.name + '.glb'] = { kind: 'npc', joints: J, surfaces: r.surfaces, anims: grp.animNames.slice(), aabb: [...r.aabb.min, ...r.aabb.max] };
		console.log(`  角色 ${grp.name}: ${J} 关节 / ${grp.animNames.join('/')} / ${r.surfaces} 材质槽 (TRS=${asLocal ? 'local' : 'global→local'})`);
	}

	/** 四元数双覆盖修复：相邻关键帧若反向（dot<0）则翻转，否则线性插值会绕远路抖动。 */
	function fixQuatContinuity(out, frames) {
		for (let f = 1; f < frames; f++) {
			let dot = 0;
			for (let c = 0; c < 4; c++) dot += out[f * 4 + c] * out[(f - 1) * 4 + c];
			if (dot < 0) for (let c = 0; c < 4; c++) out[f * 4 + c] = -out[f * 4 + c];
		}
	}

	/** 动画点云排布判定：同关节相邻帧位移 ≪ 不同关节间距。
	 *  frame-major：i 与 i+J 同关节（近）；joint-major：i 与 i+1 同关节（近）。 */
	function detectOrder(pos, N, J) {
		let dAdj = 0, nAdj = 0, dStride = 0, nStride = 0;
		for (let i = 0; i + 1 < N; i += 7) {
			dAdj += Math.abs(pos[i * 3] - pos[(i + 1) * 3]) + Math.abs(pos[i * 3 + 1] - pos[(i + 1) * 3 + 1]) + Math.abs(pos[i * 3 + 2] - pos[(i + 1) * 3 + 2]);
			nAdj++;
			if (i + J < N) {
				dStride += Math.abs(pos[i * 3] - pos[(i + J) * 3]) + Math.abs(pos[i * 3 + 1] - pos[(i + J) * 3 + 1]) + Math.abs(pos[i * 3 + 2] - pos[(i + J) * 3 + 2]);
				nStride++;
			}
		}
		return (nStride ? dStride / nStride : 1e9) < (nAdj ? dAdj / nAdj : 1e9) ? 'frame' : 'joint';
	}

	function packGLB(json, bin) {
		const enc = new TextEncoder();
		let js = enc.encode(JSON.stringify(json));
		if (js.length % 4) js = new Uint8Array([...js, ...new Uint8Array(4 - (js.length % 4))]);
		const total = 12 + 8 + js.length + 8 + bin.length;
		const u8 = new Uint8Array(total);
		const dv = new DataView(u8.buffer);
		dv.setUint32(0, 0x46546c67, true);
		dv.setUint32(4, 2, true);
		dv.setUint32(8, total, true);
		dv.setUint32(12, js.length, true);
		dv.setUint32(16, 0x4e4f534a, true);
		u8.set(js, 20);
		const binOff = 20 + js.length;
		dv.setUint32(binOff, bin.length, true);
		dv.setUint32(binOff + 4, 0x004e4942, true);
		u8.set(bin, binOff + 8);
		return Buffer.from(u8);
	}

	// ---------------- 遍历 & 分组 ----------------

	fs.mkdirSync(OUT_NPC, { recursive: true });
	fs.mkdirSync(OUT_ENV, { recursive: true });

	const files = fs.readdirSync(SRC).filter(f => f.endsWith('.drc')).sort();
	const stems = files.map(f => f.replace(/\.drc$/, '').replace(/^assets_geometries_/, ''));
	const byStem = new Map();
	for (let i = 0; i < files.length; i++) byStem.set(stems[i], path.join(SRC, files[i]));

	/** npc stem 拆解：npcs_present_<group>_<file>（group 无下划线时两者相同）。
	 *  fox_fox → group=fox/file=fox；office-worker_office-worker-idle → group=office-worker/file=office-worker-idle */
	function splitNpc(stem) {
		const rest = stem.slice('npcs_present_'.length);
		const us = rest.indexOf('_');
		return us < 0 ? { group: rest, file: rest } : { group: rest.slice(0, us), file: rest.slice(us + 1) };
	}

	const npcGroups = new Map();
	const envStems = [];
	for (const stem of stems) {
		if (stem.startsWith('npcs_present_')) {
			const { group, file } = splitNpc(stem);
			if (!npcGroups.has(group)) npcGroups.set(group, { name: group, mesh: null, bones: null, anims: [], animNames: [], extraMeshes: [] });
			const grp = npcGroups.get(group);
			if (file === group) grp.mesh = byStem.get(stem);
			else if (file === group + '-bones') grp.bones = byStem.get(stem);
			else if (file.startsWith(group + '-')) { grp.anims.push(byStem.get(stem)); grp.animNames.push(file.slice(group.length + 1)); }
			else grp.extraMeshes.push(byStem.get(stem)); // 如 office-worker-alt：独立网格
		} else envStems.push(stem);
	}

	console.log(`发现 ${stems.length} 个 .drc：${npcGroups.size} 个角色组 / ${envStems.length} 个环境资产\n`);

	for (const [name, grp] of npcGroups) {
		if (!grp.mesh || !grp.bones) { console.warn(`角色组 ${name} 缺 mesh/bones，跳过`); continue; }
		try {
			writeCharacter(path.join(OUT_NPC, name + '.glb'), grp);
			for (const extra of grp.extraMeshes) {
				const dec = decodeDrc(extra);
				if (!dec.isMesh) { console.log(`  跳过点云 ${path.basename(extra)}（曲线/粒子）`); continue; }
				const stem = [...byStem.entries()].find(([, v]) => v === extra)[0];
				const file = splitNpc(stem).file;
				writeStatic(path.join(OUT_NPC, file + '.glb'), dec, file);
				console.log(`  附加网格 ${file}`);
			}
		} catch (e) { fails.push(`${name}: ${e.message}`); console.error(`✗ ${name}: ${e.message}`); }
	}

	for (const stem of envStems) {
		try {
			const dec = decodeDrc(byStem.get(stem));
			if (!dec.isMesh) { console.log(`  跳过点云 ${stem}（曲线/粒子，无网格语义）`); continue; }
			writeStatic(path.join(OUT_ENV, stem + '.glb'), dec, stem);
			console.log(`  静态 ${stem}: ${dec.geom.num_points()} 顶点, ${manifest.files[stem + '.glb'].surfaces} 材质槽`);
		} catch (e) { fails.push(`${stem}: ${e.message}`); console.error(`✗ ${stem}: ${e.message}`); }
	}

	fs.writeFileSync(path.join(ROOT, 'assets', 'art', 'manifest.json'), JSON.stringify(manifest, null, 2));
	console.log(`\n完成：${Object.keys(manifest.files).length} 个 glb，失败 ${fails.length}`);
	if (fails.length) { console.log(fails.join('\n')); process.exitCode = 1; }
}

main();
