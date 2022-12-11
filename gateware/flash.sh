#!/bin/sh

dfu-util -d 1d50:6159,:6156 -a 0 -D redip_sid.bin -R
