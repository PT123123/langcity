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
    ok = 0
    fail = []
    for w in data["words"]:
        text = w.get("kana") or w.get("ja", "")
        if not text:
            continue
        if await gen(w["id"], text):
            w["audio"] = "res://assets/audio/%s.mp3" % w["id"]
            ok += 1
            print("  ✓", w["id"], text)
        else:
            fail.append(w["id"])
    io.open(WORDS_PATH, "w", encoding="utf-8", newline="\n").write(
        json.dumps(data, ensure_ascii=False, indent=2))
    print("完成 %d/%d" % (ok, len(data["words"])))
    if fail:
        print("失败列表:", fail)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
