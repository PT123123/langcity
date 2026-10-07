// art-assets .ktx2 → .png 解码器（Basis Universal → RGBA8）。
//
// 【为什么需要】Godot 4.4 没有 ktx2 导入器，而这些贴图是原版质感的核心：
// 树叶/草地/水面波浪/云/三层噪声/星系天穹/LUT 色彩分级。npm 上没有独立的
// basis 解码包，这里用 three.js 自带的 basis_transcoder（jsdelivr 拉的
// UMD 版 js+wasm，调用姿势照抄 three 的 KTX2Loader）转成 cTFRGBA32 写 PNG。
//
// 用法：node tools/art_convert/ktx2png.mjs [输入目录]
//   默认输入 assets/tex/art/，PNG 写同目录同名。

import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const require_ = createRequire(import.meta.url);
// 注意：本包 package.json 是 "type": "module"，UMD 的 js 必须用 .cjs 后缀 require
const BASIS = require_('./basis_transcoder.cjs');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..');
const DIR = process.argv[2] ? path.resolve(ROOT, process.argv[2]) : path.join(ROOT, 'assets', 'tex', 'art');

// basis transcoder 目标格式：cTFRGBA32 = 13（未压缩 RGBA8，任何源都能转）
const cTFRGBA32 = 13;

// ---------------- 最小 PNG 编码器（RGBA8，filter 0）----------------

const crcTable = (() => {
	const t = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
		t[n] = c >>> 0;
	}
	return t;
})();

function crc32(buf) {
	let c = 0xFFFFFFFF;
	for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
	return (c ^ 0xFFFFFFFF) >>> 0;
}

function chunk(type, data) {
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length);
	const t = Buffer.from(type, 'ascii');
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
	return Buffer.concat([len, t, data, crc]);
}

function encodePNG(w, h, rgba) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;  // bit depth
	ihdr[9] = 6;  // RGBA
	const stride = w * 4;
	const raw = Buffer.alloc(h * (stride + 1));
	for (let y = 0; y < h; y++) {
		raw[y * (stride + 1)] = 0;  // filter none
		rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
	}
	return Buffer.concat([
		Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
		chunk('IHDR', ihdr),
		chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
		chunk('IEND', Buffer.alloc(0)),
	]);
}

// ---------------- 主流程 ----------------

const wasm = fs.readFileSync(path.join(__dirname, 'basis_transcoder.wasm'));
// 照抄 three KTX2Loader 的初始化：工厂把 API 填进传入的配置对象本身
let BasisModule = null;
await new Promise((resolve) => {
	BasisModule = { wasmBinary: wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength), onRuntimeInitialized: resolve };
	BASIS(BasisModule);
});
BasisModule.initializeBasis();
if (BasisModule.KTX2File === undefined) {
	console.error('transcoder 过旧：无 KTX2File');
	process.exit(1);
}

const files = fs.readdirSync(DIR).filter(f => f.endsWith('.ktx2'));
let fails = 0;
for (const f of files) {
	const src = path.join(DIR, f);
	const out = path.join(DIR, f.replace(/\.ktx2$/, '.png'));
	let ktx2File = null;
	try {
		const bytes = fs.readFileSync(src);
		ktx2File = new BasisModule.KTX2File(new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength));
		if (!ktx2File.isValid()) throw new Error('invalid .ktx2');
		const w = ktx2File.getWidth(), h = ktx2File.getHeight();
		const layerCount = ktx2File.getLayers() || 1;
		const levelCount = ktx2File.getLevels();
		const faceCount = ktx2File.getFaces();
		if (faceCount !== 1) throw new Error('cubemap/数组贴图暂不支持');
		if (!ktx2File.startTranscoding()) throw new Error('startTranscoding 失败');
		// 只转 mip0（游戏内 Godot 会自己生成 mipmap）
		const info = ktx2File.getImageLevelInfo(0, 0, 0);
		const tw = levelCount > 1 ? info.origWidth : info.width;
		const th = levelCount > 1 ? info.origHeight : info.height;
		const dst = new Uint8Array(ktx2File.getImageTranscodedSizeInBytes(0, 0, 0, cTFRGBA32));
		if (!ktx2File.transcodeImage(dst, 0, 0, 0, cTFRGBA32, 0, -1, -1)) throw new Error('transcodeImage 失败');
		fs.writeFileSync(out, encodePNG(tw, th, Buffer.from(dst.buffer, dst.byteOffset, dst.length)));
		console.log(`✓ ${f}: ${w}x${h} uastc=${ktx2File.isUASTC()} alpha=${ktx2File.getHasAlpha()} -> ${path.basename(out)}`);
		ktx2File.close();
		ktx2File.delete();
		ktx2File = null;
	} catch (e) {
		fails++;
		console.error(`✗ ${f}: ${e.message}`);
		if (ktx2File) { try { ktx2File.close(); ktx2File.delete(); } catch { /* 忽略 */ } }
	}
}
console.log(`完成 ${files.length - fails}/${files.length}`);
if (fails) process.exitCode = 1;
