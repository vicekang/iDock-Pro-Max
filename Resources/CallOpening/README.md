# Bundled Chinese opening audio

These are local fallback recordings, generated with the macOS Tingting voice for this personal experimental fork. No speech synthesis or network request occurs when they are played. Both files are mono PCM16 WAV at 8 kHz.

- `greeting.wav`: 您好，我是机主的 AI 电话助理。请问有什么可以帮您转达？
- `recording-notice.wav`: 本次通话会录音并保存文字。

Generate equivalent source material with `say -v Tingting` (rates 205 and 220 respectively), then convert with `afconvert -f WAVE -d LEI16@8000 -c 1`. The app performs its normal trim, level and padding pass before caching these files. Users can import their own recordings in CellDock settings.
