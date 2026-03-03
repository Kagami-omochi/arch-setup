#!/usr/bin/env bash

if obs-cmd replay save; then
  notify-send "リプレイ保存" "直前のリプレイを保存しました"
else
  notify-send "⚠ リプレイ保存失敗" "リプレイバッファが有効になっていません"
fi
