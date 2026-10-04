# -*- coding: utf-8 -*-
"""
为词库生成发音音频（微软神经日语语音 ja-JP-NanamiNeural）。
输出 assets/audio/<id>.mp3，并回写 data/words.json 的 audio 字段。
用法：python tools/gen_audio.py
"""
import asyncio
import io
import json
import os
import sys

import edge_tts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
WORDS_PATH = os.path.join(ROOT, "data", "words.json")
VOICE = "ja-JP-NanamiNeural"


async def gen(word_id: str, text: str, retries: int = 3) -> bool:
    out = os.path.join(AUDIO_DIR, word_id + ".mp3")
    if os.path.exists(out) and os.path.getsize(out) > 3000:
        return True
    for attempt in range(retries):
        try:
            communicate = edge_tts.Communicate(text, VOICE, rate="-10%")
            await communicate.save(out)
            return os.path.getsize(out) > 3000
        except Exception as e:
            if attempt == retries - 1:
                print("  失败:", word_id, repr(e)[:100])
                return False
            await asyncio.sleep(2.0)
    return False


async def main() -> None:
    os.makedirs(AUDIO_DIR, exist_ok=True)
    data = json.load(io.open(WORDS_PATH, encoding="utf-8"))
    sem = asyncio.Semaphore(8)   # 并发 8：太多会被 edge-tts 限流

    async def job(w):
        text = w.get("kana") or w.get("ja", "")
        if not text:
            return w["id"], True
        async with sem:
            ok = await gen(w["id"], text)
        return w["id"], ok

    results = await asyncio.gather(*[job(w) for w in data["words"]])
    ok = 0
    fail = []
    for wid, good in results:
        if good:
            w = next(x for x in data["words"] if x["id"] == wid)
            w["audio"] = "res://assets/audio/%s.mp3" % wid
            ok += 1
            print("  ✓", wid)
        else:
            fail.append(wid)
    io.open(WORDS_PATH, "w", encoding="utf-8", newline="\n").write(
        json.dumps(data, ensure_ascii=False, indent=2))
    print("完成 %d/%d" % (ok, len(data["words"])))
    if fail:
        print("失败列表:", fail)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
