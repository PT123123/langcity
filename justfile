# 日语街道（Nihongo Street）常用任务
# 依赖：just、adb（安卓调试桥）、python3

# 列出所有可用任务（默认）
default:
    @just --list

# 安装 APK 到已连接的安卓设备（仅安装，不启动；需先在 Godot 里导出 APK）
installandroid:
    adb install -r build/nihongo-street.apk

# 下载外部素材：Poly Haven CC0 贴图 + edge-tts 生成单词发音音频（增量，已有文件会跳过）
download-resource:
    python tools/fetch_textures.py
    python tools/gen_audio.py

# 清理临时产物：.godot 导入缓存、out/ 开发截图
# 不清理 assets/（素材）与 build/（APK 产物）
clean:
    -rm -rf .godot out
