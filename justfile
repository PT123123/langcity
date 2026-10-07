# 日语街道（Nihongo Street）常用任务
# 依赖：just、adb（安卓调试桥）、python3

# 列出所有可用任务（默认）
default:
    @just --list

# 在电脑端运行游戏做测试（用仓库自带的便携版 Godot 4.4.1，无需另装引擎）
run:
    "{{justfile_directory()}}/_tools/Godot_v4.4.1-stable_win64.exe" --path "{{justfile_directory()}}"

# 打开星球地图编辑器（相机/WASD 随时可用；增删/移动/旋转/保存需勾选「编辑模式」）
edit-map:
    "{{justfile_directory()}}/_tools/Godot_v4.4.1-stable_win64.exe" --path "{{justfile_directory()}}" res://_tools/map_editor.tscn

# AI 编辑接口：无头执行 ops.json 操作清单（人物/地图/任务/对话，见 docs/AI_EDITOR_API.md）
# 用法：just ai-edit out/ops.json
ai-edit OPS:
    python "{{justfile_directory()}}/_tools/ai_edit.py" "{{OPS}}"

# 安装 APK 到已连接的安卓设备（仅安装，不启动；需先在 Godot 里导出 APK）
installandroid:
    adb install -r build/nihongo-street.apk

# 下载外部素材：Poly Haven CC0 贴图 + edge-tts 生成单词发音音频（增量，已有文件会跳过）
# 用 fetch_tex.py（44 条 WANTED 目录），不是旧的 fetch_textures.py（只有 9 条）
download-resource:
    python tools/fetch_tex.py
    python tools/gen_audio.py

# 清理临时产物：.godot 导入缓存、out/ 开发截图
# 不清理 assets/（素材）与 build/（APK 产物）
clean:
    -rm -rf .godot out
