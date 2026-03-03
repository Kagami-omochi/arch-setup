#!/usr/bin/env bash

if obs-cmd recording status | grep -q "Active: true"; then
  obs-cmd recording stop
  notify-send "■ 録画停止"
else
  obs-cmd recording start
  notify-send "● 録画開始"
fi
