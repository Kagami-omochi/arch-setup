#!/usr/bin/env bash

OUTDIR="$HOME/Pictures"
FILENAME="screenshot_$(date '+%Y-%m-%d_%H-%M-%S').png"
OUTPATH="$OUTDIR/$FILENAME"

if obs-cmd save-screenshot "スクリーンキャプチャ (PipeWire)" "png" "$OUTPATH" ; then
  notify-send -i "$OUTPATH" "スクリーンショットを保存しました" "$FILENAME"
else
  notify-send "⚠ スクリーンショット失敗" "OBSの設定や接続を確認してください"
fi
