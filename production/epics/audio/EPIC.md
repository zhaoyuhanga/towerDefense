# Epic: Audio System (音频)

> **Layer**: Polish | **V1.0** | **GDD**: design/gdd/audio.md | **Status**: Ready
> **Architecture Module**: Audio (Polish — read-only, optional in MVP)
> **Stories**: 1 story — V1.0 stub — **COMPLETE** (2026-06-02)

## Stories
| # | Story | Type | Status | Files |
|---|-------|------|--------|-------|
| 001 | Audio Manager (V1.0 stub) | Stub | Complete | audio_manager.gd (271 lines) |

## Overview

实现只读音频播放层——订阅 11+ 游戏信号，播放对应音效。每个游戏事件映射一个 OGG Vorbis 音频资源。支持 N 通道同时播放、优先级声音窃取、三个独立音量控制（master/sfx/music）、无缝循环背景音乐。MVP 中音频系统可选——所有其他系统需检查音频可用性。

## Governing ADRs

| ADR | Decision | Risk |
|-----|----------|------|
| ADR-0001 | 纯信号消费者——订阅信号，写零游戏状态 | LOW |

## GDD Requirements (10 TRs)

全部为 V1.0 实现细节。无独立 ADR 需求。

## Definition of Done (V1.0)

- 11+ 事件→音效映射
- AudioStreamPlayer 池——N 通道无串扰
- 音量控制管线（master/sfx/music 三滑块）
- 优雅降级至静默模式（音频文件缺失=不报错）
- 无缝循环背景音乐
- SFX 优先级 + 声音窃取
- 运行时音量即时变更
- OGG Vorbis 格式
