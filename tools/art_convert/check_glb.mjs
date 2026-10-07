// 快速诊断：解包 glb 的 JSON chunk，校验 accessor/bufferView 边界与索引越界
// 用法：node check_glb.mjs <file.glb>
import fs from 'node:fs';

const file = process.argv[2];
const buf = fs.readFileSync(file);
const jsonLen = buf.readUInt32LE(12);
const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('latin1').replace(/[\0\s]+$/, ''));
const binStart = 20 + jsonLen + 8;
const binLen = buf.readUInt32LE(20 + jsonLen);
const bin = buf.subarray(binStart, binStart + binLen);

const CT = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };
const NC = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
let errs = 0;
const bad = (m) => { console.log('✗ ' + m); errs++; };

console.log(`meshes=${json.meshes?.length} accessors=${json.accessors?.length} bufferViews=${json.bufferViews?.length} materials=${json.materials?.length} binLen=${binLen}`);

for (const [i, bv] of (json.bufferViews || []).entries()) {
	if (bv.byteOffset + bv.byteLength > binLen) bad(`bufferView[${i}] 越界: off=${bv.byteOffset} len=${bv.byteLength} > ${binLen}`);
}
for (const [i, a] of (json.accessors || []).entries()) {
	const size = CT[a.componentType] * NC[a.type] * a.count;
	if (a.bufferView != null) {
		const bv = json.bufferViews[a.bufferView];
		const off = (bv.byteOffset || 0) + (a.byteOffset || 0);
		if (off + size > binLen) bad(`accessor[${i}] 越界: off=${off} size=${size}`);
		if ((off % CT[a.componentType]) !== 0) bad(`accessor[${i}] 未对齐: off=${off} ct=${a.componentType}`);
	}
	if (a.type === 'VEC3' && a.min?.length !== 3) bad(`accessor[${i}] POSITION min/max 缺失`);
}
// 索引越界 + 网格 attributes 检查
for (const [mi, m] of (json.meshes || []).entries()) {
	for (const [pi, p] of (m.primitives ?? []).entries()) {
		if (p.mode !== 4 && p.mode != null) bad(`mesh[${mi}].p[${pi}] mode=${p.mode}（非三角形）`);
		const npts = json.accessors[p.attributes.POSITION].count;
		if (p.indices != null) {
			const a = json.accessors[p.indices];
			const bv = json.bufferViews[a.bufferView];
			const off = (bv.byteOffset || 0);
			if (a.componentType !== 5125 && a.componentType !== 5123) bad(`mesh[${mi}].p[${pi}] 索引类型 ${a.componentType}`);
			for (let k = 0; k < a.count; k++) {
				const v = a.componentType === 5125 ? bin.readUInt32LE(off + k * 4) : bin.readUInt16LE(off + k * 2);
				if (v >= npts) { bad(`mesh[${mi}].p[${pi}] 索引越界: idx[${k}]=${v} >= ${npts}`); break; }
			}
		}
		for (const [an, ai] of Object.entries(p.attributes)) {
			const ac = json.accessors[ai];
			if (ac.count !== npts) bad(`mesh[${mi}].p[${pi}] 属性 ${an} count=${ac.count} ≠ POSITION ${npts}`);
		}
	}
}
// 动画 sampler 输入的 min/max（Godot 对某些 accessor 边界挑剔）
for (const [ai, an] of (json.animations || []).entries()) {
	for (const [si, s] of an.samplers.entries()) {
		const a = json.accessors[s.input];
		if (a.min == null || a.max == null) bad(`animation[${ai}].sampler[${si}] input 缺 min/max`);
	}
}
console.log(errs === 0 ? '结构 OK' : `共 ${errs} 处问题`);
